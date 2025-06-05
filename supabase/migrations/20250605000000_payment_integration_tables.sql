-- supabase/migrations/20250605000000_payment_integration_tables.sql

-- Create subscription plans table
CREATE TABLE IF NOT EXISTS subscription_plans (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  price DECIMAL(10, 2) NOT NULL,
  currency VARCHAR(3) NOT NULL DEFAULT 'USD',
  billing_interval VARCHAR(20) NOT NULL DEFAULT 'monthly', -- 'monthly', 'yearly', 'weekly', 'one_time'
  duration_months INTEGER NOT NULL DEFAULT 1,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  features JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create user subscriptions table
CREATE TABLE IF NOT EXISTS user_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id UUID NOT NULL REFERENCES subscription_plans(id),
  subscription_type VARCHAR(20) NOT NULL DEFAULT 'premium',
  payment_processor VARCHAR(20) NOT NULL, -- 'stripe', 'paypal', etc.
  payment_status VARCHAR(20) NOT NULL DEFAULT 'active', -- 'active', 'cancelled', 'expired', 'trial'
  external_subscription_id VARCHAR(255),
  external_payment_id VARCHAR(255),
  last_payment_date TIMESTAMP WITH TIME ZONE,
  expiry_date TIMESTAMP WITH TIME ZONE NOT NULL,
  cancelled_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create payment transactions table
CREATE TABLE IF NOT EXISTS payment_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id UUID REFERENCES subscription_plans(id),
  amount DECIMAL(10, 2) NOT NULL,
  currency VARCHAR(3) NOT NULL DEFAULT 'USD',
  payment_processor VARCHAR(20) NOT NULL, -- 'stripe', 'paypal', etc.
  transaction_id VARCHAR(255) NOT NULL,
  external_subscription_id VARCHAR(255),
  external_payment_id VARCHAR(255),
  status VARCHAR(20) NOT NULL, -- 'completed', 'pending', 'failed', 'refunded'
  transaction_date TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create payment sessions table for tracking checkout sessions
CREATE TABLE IF NOT EXISTS payment_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id VARCHAR(255) NOT NULL UNIQUE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id UUID REFERENCES subscription_plans(id),
  payment_processor VARCHAR(20) NOT NULL,
  amount DECIMAL(10, 2),
  currency VARCHAR(3),
  status VARCHAR(20) NOT NULL DEFAULT 'pending', -- 'pending', 'complete', 'failed', 'cancelled'
  external_subscription_id VARCHAR(255),
  external_payment_id VARCHAR(255),
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create user payment methods table
CREATE TABLE IF NOT EXISTS user_payment_methods (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  payment_provider VARCHAR(20) NOT NULL, -- 'stripe', 'paypal', etc.
  provider_customer_id VARCHAR(255),
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  last_four VARCHAR(4),
  card_type VARCHAR(20),
  expiry_month INTEGER,
  expiry_year INTEGER,
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create payment configuration table
CREATE TABLE IF NOT EXISTS payment_configuration (
  id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- Ensures only one record
  stripe_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  paypal_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  demo_mode BOOLEAN NOT NULL DEFAULT FALSE,
  tax_percentage DECIMAL(5, 2) NOT NULL DEFAULT 0.0,
  currency VARCHAR(3) NOT NULL DEFAULT 'USD',
  settings JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default payment configuration
INSERT INTO payment_configuration
  (stripe_enabled, paypal_enabled, demo_mode, tax_percentage, currency, settings)
VALUES
  (TRUE, TRUE, TRUE, 0.0, 'USD', '{"allow_trial": true, "trial_days": 14}')
ON CONFLICT (id) DO NOTHING;

-- Insert sample subscription plans
INSERT INTO subscription_plans
  (name, description, price, currency, billing_interval, duration_months, features)
VALUES
  (
    'Premium Monthly', 
    'Unlimited access to all premium features with monthly billing', 
    9.99, 
    'USD', 
    'monthly', 
    1, 
    '[
      {"id": "offline", "name": "Offline Listening", "description": "Download music for offline listening", "tier": "premium"},
      {"id": "hq_audio", "name": "High-Quality Audio", "description": "Stream in high-quality up to 320kbps", "tier": "premium"},
      {"id": "no_ads", "name": "Ad-Free", "description": "Enjoy music without interruptions", "tier": "premium"},
      {"id": "unlimited_skips", "name": "Unlimited Skips", "description": "Skip as many songs as you want", "tier": "premium"}
    ]'
  ),
  (
    'Premium Yearly', 
    'Unlimited access to all premium features with yearly billing (2 months free)', 
    99.99, 
    'USD', 
    'yearly', 
    12, 
    '[
      {"id": "offline", "name": "Offline Listening", "description": "Download music for offline listening", "tier": "premium"},
      {"id": "hq_audio", "name": "High-Quality Audio", "description": "Stream in high-quality up to 320kbps", "tier": "premium"},
      {"id": "no_ads", "name": "Ad-Free", "description": "Enjoy music without interruptions", "tier": "premium"},
      {"id": "unlimited_skips", "name": "Unlimited Skips", "description": "Skip as many songs as you want", "tier": "premium"},
      {"id": "exclusive_content", "name": "Exclusive Content", "description": "Access to exclusive content and early releases", "tier": "premium"}
    ]'
  ),
  (
    'Premium Family', 
    'Premium features for up to 6 family members living at the same address', 
    14.99, 
    'USD', 
    'monthly', 
    1, 
    '[
      {"id": "offline", "name": "Offline Listening", "description": "Download music for offline listening", "tier": "premium"},
      {"id": "hq_audio", "name": "High-Quality Audio", "description": "Stream in high-quality up to 320kbps", "tier": "premium"},
      {"id": "no_ads", "name": "Ad-Free", "description": "Enjoy music without interruptions", "tier": "premium"},
      {"id": "unlimited_skips", "name": "Unlimited Skips", "description": "Skip as many songs as you want", "tier": "premium"},
      {"id": "family_accounts", "name": "Family Accounts", "description": "Up to 6 accounts for family members", "tier": "premium"}
    ]'
  );

-- Create RLS policies
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_configuration ENABLE ROW LEVEL SECURITY;

-- Policy for subscription plans: everyone can read active plans
CREATE POLICY "Anyone can read active subscription plans"
  ON subscription_plans FOR SELECT
  USING (is_active = TRUE);

-- Policy for user subscriptions: users can read their own subscriptions
CREATE POLICY "Users can read their own subscriptions"
  ON user_subscriptions FOR SELECT
  USING (auth.uid() = user_id);

-- Policy for payment transactions: users can read their own transactions
CREATE POLICY "Users can read their own payment transactions"
  ON payment_transactions FOR SELECT
  USING (auth.uid() = user_id);

-- Policy for payment sessions: users can read their own sessions
CREATE POLICY "Users can read their own payment sessions"
  ON payment_sessions FOR SELECT
  USING (auth.uid() = user_id);

-- Policy for user payment methods: users can read their own payment methods
CREATE POLICY "Users can read their own payment methods"
  ON user_payment_methods FOR SELECT
  USING (auth.uid() = user_id);

-- Policy for payment configuration: anyone can read
CREATE POLICY "Anyone can read payment configuration"
  ON payment_configuration FOR SELECT
  USING (true);

-- Create indices for performance
CREATE INDEX IF NOT EXISTS user_subscriptions_user_id_idx ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS payment_transactions_user_id_idx ON payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS payment_sessions_session_id_idx ON payment_sessions(session_id);
CREATE INDEX IF NOT EXISTS payment_sessions_user_id_idx ON payment_sessions(user_id);
CREATE INDEX IF NOT EXISTS user_payment_methods_user_id_idx ON user_payment_methods(user_id);
