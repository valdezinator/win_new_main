// supabase/functions/create-stripe-checkout/index.ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.21.0'
import Stripe from 'https://esm.sh/stripe@12.6.0?dts'

// Initialize Stripe with the secret key from environment variables
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
})

// Get the URL of the Supabase project
const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const supabase = createClient(supabaseUrl, supabaseKey)

serve(async (req) => {
  try {
    // Parse the request body
    const { plan_id, amount, currency, description, user_id, customer_id } = await req.json()

    if (!plan_id || !amount || !currency || !user_id) {
      return new Response(
        JSON.stringify({
          error: 'Missing required parameters',
        }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Get the URL for success and cancel redirect
    const baseUrl = Deno.env.get('CLIENT_URL') || 'http://localhost:3000'
    const successUrl = `${baseUrl}/payment-success?session_id={CHECKOUT_SESSION_ID}`
    const cancelUrl = `${baseUrl}/payment-cancel`

    // Create a Stripe customer if customer_id is not provided
    let stripeCustomerId = customer_id

    if (!stripeCustomerId) {
      // Get user from Supabase
      const { data: userData, error: userError } = await supabase
        .from('profiles')
        .select('email, full_name')
        .eq('id', user_id)
        .single()

      if (userError) {
        console.error('Error fetching user data:', userError)
        return new Response(
          JSON.stringify({ error: 'Error fetching user data' }),
          { status: 500, headers: { 'Content-Type': 'application/json' } }
        )
      }

      // Create a customer in Stripe
      const customer = await stripe.customers.create({
        email: userData.email,
        name: userData.full_name,
        metadata: { user_id: user_id },
      })

      stripeCustomerId = customer.id

      // Store the Stripe customer ID in the database
      await supabase
        .from('user_payment_methods')
        .upsert({
          user_id: user_id,
          payment_provider: 'stripe',
          provider_customer_id: stripeCustomerId,
        })
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

    // Create a checkout session
    const session = await stripe.checkout.sessions.create({
      customer: stripeCustomerId,
      line_items: [
        {
          price_data: {
            currency: currency,
            product_data: {
              name: planData.name,
              description: description,
            },
            unit_amount: Math.round(amount * 100), // Convert to cents
            recurring: planData.billing_interval !== 'one_time' ? {
              interval: planData.billing_interval === 'yearly' ? 'year' : planData.billing_interval,
              interval_count: 1,
            } : undefined,
          },
          quantity: 1,
        },
      ],
      mode: planData.billing_interval !== 'one_time' ? 'subscription' : 'payment',
      success_url: successUrl,
      cancel_url: cancelUrl,
      metadata: {
        user_id: user_id,
        plan_id: plan_id,
      },
    })

    // Return the checkout session ID and URL
    return new Response(
      JSON.stringify({
        session_id: session.id,
        url: session.url,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error creating checkout session:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
