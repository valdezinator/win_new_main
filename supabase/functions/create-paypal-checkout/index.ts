// supabase/functions/create-paypal-checkout/index.ts
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
    const { plan_id, amount, currency, description, user_id } = await req.json()

    if (!plan_id || !amount || !currency || !user_id) {
      return new Response(
        JSON.stringify({
          error: 'Missing required parameters',
        }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Get the plan from the database
    const { data: planData, error: planError } = await supabase
      .from('subscription_plans')
      .select('*')
      .eq('id', plan_id)
      .single()

    if (planError) {
      console.error('Error fetching plan:', planError)
      return new Response(
        JSON.stringify({ error: 'Error fetching plan' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Get PayPal access token
    const accessToken = await getAccessToken()
    
    // Get the URL for success and cancel redirect
    const baseUrl = Deno.env.get('CLIENT_URL') || 'http://localhost:3000'
    const successUrl = `${baseUrl}/payment-success?source=paypal`
    const cancelUrl = `${baseUrl}/payment-cancel`

    // Create a PayPal order
    const order = {
      intent: 'CAPTURE',
      purchase_units: [{
        amount: {
          currency_code: currency.toUpperCase(),
          value: amount.toString(),
        },
        description: description,
      }],
      application_context: {
        brand_name: 'Music Streaming App',
        landing_page: 'BILLING',
        user_action: 'PAY_NOW',
        return_url: successUrl,
        cancel_url: cancelUrl,
      },
    }

    // If subscription, use different API
    let paypalResponse
    let session_id
    let url

    if (planData.billing_interval !== 'one_time') {
      // Create a subscription product if not exists
      const productResponse = await fetch(`${PAYPAL_API_URL}/v1/catalogs/products`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          name: planData.name,
          description: description,
          type: 'SERVICE',
          category: 'DIGITAL_MEDIA_BOOKS_MOVIES_MUSIC',
        }),
      })

      const product = await productResponse.json()
      
      // Create a plan for the product
      const planResponse = await fetch(`${PAYPAL_API_URL}/v1/billing/plans`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          product_id: product.id,
          name: planData.name,
          billing_cycles: [{
            frequency: {
              interval_unit: planData.billing_interval === 'yearly' ? 'YEAR' : 
                            planData.billing_interval === 'monthly' ? 'MONTH' : 'WEEK',
              interval_count: 1,
            },
            tenure_type: 'REGULAR',
            sequence: 1,
            total_cycles: 0, // Infinite until cancelled
            pricing_scheme: {
              fixed_price: {
                value: amount.toString(),
                currency_code: currency.toUpperCase(),
              },
            },
          }],
          payment_preferences: {
            auto_bill_outstanding: true,
            setup_fee: {
              value: '0',
              currency_code: currency.toUpperCase(),
            },
            setup_fee_failure_action: 'CONTINUE',
            payment_failure_threshold: 3,
          },
          taxes: {
            percentage: '0',
            inclusive: false,
          },
        }),
      })

      const paypalPlan = await planResponse.json()
      
      // Create a subscription
      const subscriptionResponse = await fetch(`${PAYPAL_API_URL}/v1/billing/subscriptions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          plan_id: paypalPlan.id,
          application_context: {
            brand_name: 'Music Streaming App',
            locale: 'en-US',
            shipping_preference: 'NO_SHIPPING',
            user_action: 'SUBSCRIBE_NOW',
            payment_method: {
              payer_selected: 'PAYPAL',
              payee_preferred: 'IMMEDIATE_PAYMENT_REQUIRED',
            },
            return_url: successUrl,
            cancel_url: cancelUrl,
          },
          custom_id: JSON.stringify({
            user_id,
            plan_id,
          }),
        }),
      })

      paypalResponse = await subscriptionResponse.json()
      session_id = paypalResponse.id
      
      // Find the approval URL
      const approvalLink = paypalResponse.links.find(link => link.rel === 'approve')
      url = approvalLink ? approvalLink.href : null
    } else {
      // One-time payment
      const orderResponse = await fetch(`${PAYPAL_API_URL}/v2/checkout/orders`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          ...order,
          purchase_units: [{
            ...order.purchase_units[0],
            custom_id: JSON.stringify({
              user_id,
              plan_id,
            }),
          }],
        }),
      })

      paypalResponse = await orderResponse.json()
      session_id = paypalResponse.id
      
      // Find the approval URL
      const approvalLink = paypalResponse.links.find(link => link.rel === 'approve')
      url = approvalLink ? approvalLink.href : null
    }

    if (!url) {
      return new Response(
        JSON.stringify({ error: 'Could not create PayPal checkout URL' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Store the session in the database
    await supabase.from('payment_sessions').insert({
      session_id,
      user_id,
      plan_id,
      payment_processor: 'paypal',
      amount,
      currency,
      status: 'pending',
      metadata: paypalResponse,
    })

    // Return the checkout session ID and URL
    return new Response(
      JSON.stringify({
        session_id,
        url,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error creating PayPal checkout:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
