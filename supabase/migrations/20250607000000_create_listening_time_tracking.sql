-- Create user listening time tracking table
CREATE TABLE IF NOT EXISTS user_listening_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  session_start TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  session_end TIMESTAMP WITH TIME ZONE,
  total_listening_minutes INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create user daily listening time summary table
CREATE TABLE IF NOT EXISTS user_daily_listening (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  date DATE NOT NULL,
  total_minutes INTEGER DEFAULT 0,
  session_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, date)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_listening_sessions_user_id ON user_listening_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_listening_sessions_active ON user_listening_sessions(is_active);
CREATE INDEX IF NOT EXISTS idx_user_daily_listening_user_date ON user_daily_listening(user_id, date);

-- Enable Row Level Security
ALTER TABLE user_listening_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_daily_listening ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Users can manage their own listening sessions"
  ON user_listening_sessions FOR ALL
  USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own daily listening data"
  ON user_daily_listening FOR ALL
  USING (auth.uid() = user_id);

-- Function to start a new listening session
CREATE OR REPLACE FUNCTION start_listening_session(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
  session_id UUID;
BEGIN
  -- End any existing active session for this user
  UPDATE user_listening_sessions 
  SET session_end = NOW(), is_active = false, updated_at = NOW()
  WHERE user_id = p_user_id AND is_active = true;
  
  -- Create new session
  INSERT INTO user_listening_sessions (user_id, session_start, is_active)
  VALUES (p_user_id, NOW(), true)
  RETURNING id INTO session_id;
  
  RETURN session_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to end a listening session and update daily totals
CREATE OR REPLACE FUNCTION end_listening_session(p_user_id UUID, p_minutes_listened INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
  session_record RECORD;
  session_minutes INTEGER;
BEGIN
  -- Get the active session
  SELECT * INTO session_record 
  FROM user_listening_sessions 
  WHERE user_id = p_user_id AND is_active = true
  ORDER BY session_start DESC 
  LIMIT 1;
  
  IF session_record IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Calculate session duration in minutes
  session_minutes = EXTRACT(EPOCH FROM (NOW() - session_record.session_start)) / 60;
  
  -- Update session with end time and total minutes
  UPDATE user_listening_sessions 
  SET 
    session_end = NOW(),
    total_listening_minutes = session_minutes,
    is_active = false,
    updated_at = NOW()
  WHERE id = session_record.id;
  
  -- Update daily listening totals
  INSERT INTO user_daily_listening (user_id, date, total_minutes, session_count)
  VALUES (p_user_id, CURRENT_DATE, session_minutes, 1)
  ON CONFLICT (user_id, date) 
  DO UPDATE SET 
    total_minutes = user_daily_listening.total_minutes + session_minutes,
    session_count = user_daily_listening.session_count + 1,
    updated_at = NOW();
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user's total listening time for today
CREATE OR REPLACE FUNCTION get_user_today_listening_minutes(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
  total_minutes INTEGER;
BEGIN
  SELECT COALESCE(total_minutes, 0) INTO total_minutes
  FROM user_daily_listening
  WHERE user_id = p_user_id AND date = CURRENT_DATE;
  
  RETURN total_minutes;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has listened for at least 10 minutes today
CREATE OR REPLACE FUNCTION has_user_listened_10_minutes_today(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN get_user_today_listening_minutes(p_user_id) >= 10;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user's listening statistics
CREATE OR REPLACE FUNCTION get_user_listening_stats(p_user_id UUID, p_days INTEGER DEFAULT 30)
RETURNS TABLE (
  total_minutes INTEGER,
  total_sessions INTEGER,
  average_minutes_per_day DECIMAL,
  longest_session_minutes INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(SUM(udl.total_minutes), 0)::INTEGER as total_minutes,
    COALESCE(SUM(udl.session_count), 0)::INTEGER as total_sessions,
    COALESCE(AVG(udl.total_minutes), 0) as average_minutes_per_day,
    COALESCE(MAX(uls.total_listening_minutes), 0)::INTEGER as longest_session_minutes
  FROM user_daily_listening udl
  LEFT JOIN user_listening_sessions uls ON udl.user_id = uls.user_id
  WHERE udl.user_id = p_user_id 
    AND udl.date >= CURRENT_DATE - INTERVAL '1 day' * p_days;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; 