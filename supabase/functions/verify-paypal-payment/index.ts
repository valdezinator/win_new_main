// supabase/functions/verify-paypal-payment/index.ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.21.0'

// Get the URL of the Supabase project
const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const supabase = createClient(supabaseUrl, supabaseKey)

// PayPal API configuration
const PAYPAL_API_URL = Deno.env.get('PAYPAL_API_URL') || 'https://api-m.sandbox.paypal.com'
const PAYPAL_CLIENT_ID = Deno.env.get('PAYPAL_CLIENT_ID') || ''
const PAYPAL_CLIENT_SECRET = Deno.env.get('PAYPAL_CLIENT_SECRET') || ''

// Function to get an access token from PayPal
async function getAccessToken() {
  const auth = btoa(`${PAYPAL_CLIENT_ID}:${PAYPAL_CLIENT_SECRET}`)
  const response = await fetch(`${PAYPAL_API_URL}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': `Basic ${auth}`,
    },
    body: 'grant_type=client_credentials',
  })

  const data = await response.json()
  return data.access_token
}

serve(async (req) => {
  try {
    // Parse the request body
    const { payment_id } = await req.json()

    if (!payment_id) {
      return new Response(
        JSON.stringify({ error: 'Payment ID is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Get PayPal access token
    const accessToken = await getAccessToken()

    // Get the payment session from the database
    const { data: sessionData, error: sessionError } = await supabase
      .from('payment_sessions')
      .select('*')
      .eq('session_id', payment_id)
      .maybeSingle()

    if (sessionError) {
      console.error('Error fetching payment session:', sessionError)
      return new Response(
        JSON.stringify({ error: 'Error fetching payment session' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // If session not found, return error
    if (!sessionData) {
      return new Response(
        JSON.stringify({ error: 'Payment session not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Determine if this is an order or subscription
    const isSubscription = payment_id.startsWith('I-')
    
    let paypalResponse
    let status

    // Verify the payment with PayPal
    if (isSubscription) {
      const response = await fetch(`${PAYPAL_API_URL}/v1/billing/subscriptions/${payment_id}`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
      })

      paypalResponse = await response.json()
      status = paypalResponse.status
    } else {
      const response = await fetch(`${PAYPAL_API_URL}/v2/checkout/orders/${payment_id}`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
      })

      paypalResponse = await response.json()
      status = paypalResponse.status
    }

    // Capture the payment if it's an order and in APPROVED status
    if (!isSubscription && status === 'APPROVED') {
      const captureResponse = await fetch(`${PAYPAL_API_URL}/v2/checkout/orders/${payment_id}/capture`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
      })

      paypalResponse = await captureResponse.json()
      status = paypalResponse.status
    }

    // Map PayPal status to our status
    let paymentStatus: string
    switch (status) {
      case 'COMPLETED':
      case 'ACTIVE':
        paymentStatus = 'complete'
        break
      case 'APPROVED':
      case 'CREATED':
      case 'SAVED':
      case 'PENDING':
        paymentStatus = 'pending'
        break
      case 'SUSPENDED':
      case 'CANCELLED':
      case 'EXPIRED':
      case 'DENIED':
        paymentStatus = 'failed'
        break
      default:
        paymentStatus = 'failed'
    }

    // If payment was successful, update the subscription in the database
    if (paymentStatus === 'complete') {
      // Parse custom ID to get user_id and plan_id
      let userId, planId
      try {
        if (isSubscription) {
          const customId = paypalResponse.custom_id
          const parsedCustomId = JSON.parse(customId)
          userId = parsedCustomId.user_id
          planId = parsedCustomId.plan_id
        } else {
          const customId = paypalResponse.purchase_units[0].custom_id
          const parsedCustomId = JSON.parse(customId)
          userId = parsedCustomId.user_id
          planId = parsedCustomId.plan_id
        }
      } catch (e) {
        console.error('Error parsing custom ID:', e)
        
        // Fall back to session data
        userId = sessionData.user_id
        planId = sessionData.plan_id
      }

      if (userId && planId) {
        // Get plan details
        const { data: planData, error: planError } = await supabase
          .from('subscription_plans')
          .select('duration_months')
          .eq('id', planId)
          .single()

        if (planError) {
          console.error('Error fetching plan details:', planError)
        } else {
          // Calculate expiry date based on plan duration
          const now = new Date()
          let expiryDate: Date

          if (isSubscription) {
            // For subscriptions, use the next billing date from PayPal
            const nextBillingDate = paypalResponse.billing_info?.next_billing_time
              ? new Date(paypalResponse.billing_info.next_billing_time)
              : new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000) // Default to 30 days
            
            expiryDate = nextBillingDate
          } else {
            // For one-time payments, calculate based on plan duration
            const durationMonths = planData.duration_months || 1
            expiryDate = new Date(now)
            expiryDate.setMonth(expiryDate.getMonth() + durationMonths)
          }

          // Update or create user subscription
          await supabase
            .from('user_subscriptions')
            .upsert({
              user_id: userId,
              plan_id: planId,
              subscription_type: 'premium',
              payment_processor: 'paypal',
              payment_status: 'active',
              external_subscription_id: isSubscription ? payment_id : null,
              last_payment_date: new Date().toISOString(),
              expiry_date: expiryDate.toISOString(),
            })

          // Record the transaction
          await supabase
            .from('payment_transactions')
            .insert({
              user_id: userId,
              plan_id: planId,
              amount: isSubscription
                ? paypalResponse.billing_info?.last_payment?.amount?.value
                : paypalResponse.purchase_units[0].amount.value,
              currency: isSubscription
                ? paypalResponse.billing_info?.last_payment?.amount?.currency_code
                : paypalResponse.purchase_units[0].amount.currency_code,
              payment_processor: 'paypal',
              transaction_id: payment_id,
              external_subscription_id: isSubscription ? payment_id : null,
              status: 'completed',
              transaction_date: new Date().toISOString(),
            })
        }
      }
    }

    // Update the payment session record
    await supabase
      .from('payment_sessions')
      .update({
        status: paymentStatus,
        updated_at: new Date().toISOString(),
      })
      .eq('session_id', payment_id)

    // Return the payment status
    return new Response(
      JSON.stringify({ status }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error verifying payment:', error)
    return new Response(
      JSON.stringify({ error: error.message, status: 'failed' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
