// supabase/functions/cancel-subscription/index.ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.21.0'
import Stripe from 'https://esm.sh/stripe@12.6.0?dts'

// Get the URL of the Supabase project
const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const supabase = createClient(supabaseUrl, supabaseKey)

// Initialize Stripe with the secret key
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
})

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
    const { subscription_id, payment_processor, user_id } = await req.json()

    let userId = user_id
    let subscriptionId = subscription_id
    let paymentProcessor = payment_processor

    // If we only got user_id but not subscription_id, look it up
    if (userId && !subscriptionId) {
      const { data: subscriptionData, error } = await supabase
        .from('user_subscriptions')
        .select('external_subscription_id, payment_processor')
        .eq('user_id', userId)
        .eq('payment_status', 'active')
        .maybeSingle()

      if (error) {
        return new Response(
          JSON.stringify({ error: 'Error fetching subscription data' }),
          { status: 500, headers: { 'Content-Type': 'application/json' } }
        )
      }

      if (!subscriptionData || !subscriptionData.external_subscription_id) {
        // No active subscription found, just update the database status
        await supabase
          .from('user_subscriptions')
          .update({ 
            payment_status: 'cancelled', 
            cancelled_at: new Date().toISOString() 
          })
          .eq('user_id', userId)
        
        return new Response(
          JSON.stringify({ success: true, message: 'No active subscription to cancel' }),
          { status: 200, headers: { 'Content-Type': 'application/json' } }
        )
      }

      subscriptionId = subscriptionData.external_subscription_id
      paymentProcessor = subscriptionData.payment_processor
    }

    // Cancel with appropriate payment gateway
    if (paymentProcessor === 'stripe' && subscriptionId) {
      await stripe.subscriptions.cancel(subscriptionId)
    } else if (paymentProcessor === 'paypal' && subscriptionId) {
      const accessToken = await getAccessToken()
      
      await fetch(`${PAYPAL_API_URL}/v1/billing/subscriptions/${subscriptionId}/cancel`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          reason: 'User requested cancellation',
        }),
      })
    }

    // Update the database regardless of if we had to cancel
    // externally or not (should be idempotent)
    await supabase
      .from('user_subscriptions')
      .update({
        payment_status: 'cancelled',
        cancelled_at: new Date().toISOString(),
      })
      .eq(userId ? 'user_id' : 'external_subscription_id', userId || subscriptionId)

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error cancelling subscription:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
