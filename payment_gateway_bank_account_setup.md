# Payment Gateway Bank Account Linking Guide

This guide explains how to link a bank account to the payment gateways (Stripe and PayPal) for the Music Streaming App. This is the final step needed to enable full payment processing in production.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Stripe Setup](#stripe-setup)
3. [PayPal Setup](#paypal-setup)
4. [Testing Your Integration](#testing-your-integration)
5. [Going Live](#going-live)
6. [Security Considerations](#security-considerations)

## Prerequisites

Before you begin, make sure you have:

- A legal business entity (company, LLC, sole proprietorship)
- Business tax identification number
- Business bank account
- Legal identification of the business owner/representative
- Business address and phone number
- Completed payment gateway implementation in the app

## Stripe Setup

### Step 1: Create a Stripe Account

1. Go to [https://dashboard.stripe.com/register](https://dashboard.stripe.com/register)
2. Fill in your email address and choose a password
3. Complete the verification process

### Step 2: Complete Your Business Profile

1. In the Stripe Dashboard, go to **Settings** > **Business Settings**
2. Fill in all required details:
   - Business name
   - Business type/entity
   - Industry
   - Business website URL
   - Business description
   - Tax ID number

### Step 3: Link Your Bank Account

1. Navigate to **Settings** > **Bank Accounts and Scheduling**
2. Click **Add Bank Account**
3. Select your country and follow the instructions:
   - For US accounts: Enter your routing number and account number
   - For non-US accounts: Enter your IBAN or account details as required
4. Complete any verification steps (Stripe may make small deposits to verify)

### Step 4: Update API Keys in Environment Variables

1. In the Stripe Dashboard, go to **Developers** > **API keys**
2. Copy your **Publishable Key** and **Secret Key**
3. Update the environment variables in your Supabase project:
   ```
   STRIPE_PUBLIC_KEY=pk_live_...
   STRIPE_SECRET_KEY=sk_live_...
   ```

### Step 5: Set Up Stripe Webhooks

1. Go to **Developers** > **Webhooks** in the Stripe Dashboard
2. Click **Add Endpoint**
3. Enter your Supabase Edge Function webhook URL:
   ```
   https://[YOUR_PROJECT_REF].supabase.co/functions/v1/stripe-webhook
   ```
4. Select events to listen for:
   - `checkout.session.completed`
   - `invoice.paid`
   - `invoice.payment_failed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
5. Copy the signing secret and add it to your environment variables:
   ```
   STRIPE_WEBHOOK_SECRET=whsec_...
   ```

## PayPal Setup

### Step 1: Create a PayPal Business Account

1. Go to [https://www.paypal.com/business/open-business-account](https://www.paypal.com/business/open-business-account)
2. Click **Sign Up** and follow the registration steps
3. Verify your email address

### Step 2: Complete Your Business Information

1. Log in to your PayPal Business account
2. Navigate to **Settings** > **Business Information**
3. Fill in all required details:
   - Business name
   - Business address
   - Customer service contact
   - Tax information

### Step 3: Link Your Bank Account

1. Go to **Money** > **Banks and Cards**
2. Click **Link a Bank Account**
3. Select your bank or enter your bank details manually
4. Follow the verification process (may include small deposits or instant verification)

### Step 4: Create PayPal Developer App

1. Go to [https://developer.paypal.com/dashboard/applications/live](https://developer.paypal.com/dashboard/applications/live)
2. Click **Create App**
3. Enter a name for your app (e.g., "Music Streaming App")
4. Copy your **Client ID** and **Secret**
5. Update the environment variables in your Supabase project:
   ```
   PAYPAL_CLIENT_ID=live_...
   PAYPAL_CLIENT_SECRET=live_...
   PAYPAL_API_URL=https://api-m.paypal.com
   ```

### Step 5: Set Up PayPal Webhooks

1. In the PayPal Developer Dashboard, select your app
2. Go to **Webhooks** > **Add Webhook**
3. Enter your Supabase Edge Function webhook URL:
   ```
   https://[YOUR_PROJECT_REF].supabase.co/functions/v1/paypal-webhook
   ```
4. Subscribe to events:
   - `PAYMENT.SALE.COMPLETED`
   - `PAYMENT.SALE.DENIED`
   - `BILLING.SUBSCRIPTION.CREATED`
   - `BILLING.SUBSCRIPTION.CANCELLED`
   - `BILLING.SUBSCRIPTION.SUSPENDED`
5. Copy the webhook ID and verification token and add them to your environment variables:
   ```
   PAYPAL_WEBHOOK_ID=...
   PAYPAL_WEBHOOK_TOKEN=...
   ```

## Testing Your Integration

### For Stripe:

1. Use Stripe's test mode with test keys before switching to live mode
2. Test credit card numbers:
   - Success: `4242 4242 4242 4242`
   - Requires Authentication: `4000 0025 0000 3155`
   - Declined: `4000 0000 0000 0002`
3. Test the full payment flow from subscription to cancellation

### For PayPal:

1. Use PayPal's sandbox environment before switching to production
2. Create test accounts in the PayPal Developer Dashboard
3. Test both subscription and one-time payment flows

## Going Live

Before switching to production:

1. Complete all testing in sandbox/test environments
2. Ensure your privacy policy and terms of service are up to date
3. Verify your business information is correct in both Stripe and PayPal
4. Update all environment variables to use production API keys
5. Deploy the final version of your app
6. Monitor transactions closely during the initial launch period

## Security Considerations

1. **Never store payment card data** in your database
2. Keep your API keys secure and never expose them in client-side code
3. Implement proper authentication and authorization for payment endpoints
4. Use HTTPS for all payment-related API calls
5. Follow PCI DSS requirements if handling card data directly
6. Regularly audit payment logs for suspicious activity
7. Implement fraud prevention measures

For additional support:
- Stripe Documentation: [https://stripe.com/docs](https://stripe.com/docs)
- PayPal Developer Documentation: [https://developer.paypal.com/docs](https://developer.paypal.com/docs)
- Contact your payment processor's support team for specific questions
