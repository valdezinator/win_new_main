// supabase/functions/verify-stripe-payment/index.ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.21.0'
import Stripe from 'https://esm.sh/stripe@12.6.0?dts'

// Initialize Stripe with the secret key
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
})

// Initialize the Supabase client
const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const supabase = createClient(supabaseUrl, supabaseKey)

serve(async (req) => {
  try {
    // Parse the request body
    const { session_id } = await req.json()

    if (!session_id) {
      return new Response(
        JSON.stringify({ error: 'Session ID is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Retrieve the checkout session
    const session = await stripe.checkout.sessions.retrieve(session_id)

    // Check the payment status
    let status: string
    let subscriptionId: string | null = null
    let paymentIntentId: string | null = null

    if (session.mode === 'subscription') {
      if (session.subscription) {
        const subscription = await stripe.subscriptions.retrieve(session.subscription as string)
        status = subscription.status
        subscriptionId = subscription.id
      } else {
        status = 'incomplete'
      }
    } else {
      if (session.payment_intent) {
        const paymentIntent = await stripe.paymentIntents.retrieve(session.payment_intent as string)
        status = paymentIntent.status
        paymentIntentId = paymentIntent.id
      } else {
        status = 'failed'
      }
    }

    // Map Stripe status to our status
    let paymentStatus: string
    switch (status) {
      case 'active':
      case 'succeeded':
      case 'paid':
        paymentStatus = 'complete'
        break
      case 'trialing':
        paymentStatus = 'trial'
        break
      case 'incomplete':
      case 'past_due':
      case 'unpaid':
      case 'requires_payment_method':
      case 'requires_confirmation':
      case 'requires_action':
      case 'processing':
        paymentStatus = 'pending'
        break
      default:
        paymentStatus = 'failed'
    }

    // If payment was successful, update the subscription in the database
    if (paymentStatus === 'complete' && session.metadata?.user_id && session.metadata?.plan_id) {
      const userId = session.metadata.user_id
      const planId = session.metadata.plan_id

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

        if (session.mode === 'subscription') {
          // For subscriptions, we'll rely on webhooks to keep this updated
          expiryDate = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000) // Default to 30 days
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
            payment_processor: 'stripe',
            payment_status: 'active',
            external_subscription_id: subscriptionId,
            external_payment_id: paymentIntentId,
            last_payment_date: new Date().toISOString(),
            expiry_date: expiryDate.toISOString(),
          })

        // Record the transaction
        await supabase
          .from('payment_transactions')
          .insert({
            user_id: userId,
            plan_id: planId,
            amount: session.amount_total ? session.amount_total / 100 : null,
            currency: session.currency?.toUpperCase(),
            payment_processor: 'stripe',
            transaction_id: session.id,
            external_subscription_id: subscriptionId,
            external_payment_id: paymentIntentId,
            status: 'completed',
            transaction_date: new Date().toISOString(),
          })
      }
    }

    // Update the payment session record
    await supabase
      .from('payment_sessions')
      .upsert({
        session_id,
        payment_processor: 'stripe',
        status: paymentStatus,
        external_subscription_id: subscriptionId,
        external_payment_id: paymentIntentId,
        updated_at: new Date().toISOString(),
      })

    // Return the payment status
    return new Response(
      JSON.stringify({ status: paymentStatus }),
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
