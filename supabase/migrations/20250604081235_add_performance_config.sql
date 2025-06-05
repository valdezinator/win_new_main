-- Performance Monitoring Configuration
-- This file contains configuration settings for performance monitoring

-- Create the configuration table
CREATE TABLE IF NOT EXISTS monitoring.config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by UUID
);

-- Insert default configuration settings
INSERT INTO monitoring.config (key, value, description) VALUES
('query_performance_thresholds', 
  '{
    "slow_query_threshold_ms": 500,
    "very_slow_query_threshold_ms": 1000,
    "alert_threshold_ms": 2000,
    "log_all_queries": false,
    "sample_rate": 0.1
  }',
  'Thresholds for query performance monitoring'
)
ON CONFLICT (key) DO NOTHING;

INSERT INTO monitoring.config (key, value, description) VALUES
('memory_monitoring', 
  '{
    "table_size_alert_threshold_mb": 1000,
    "growth_rate_alert_threshold_percent": 20,
    "check_interval_hours": 24,
    "leak_detection_threshold": 0.05
  }',
  'Configuration for memory usage monitoring'
)
ON CONFLICT (key) DO NOTHING;

INSERT INTO monitoring.config (key, value, description) VALUES
('api_performance_thresholds', 
  '{
    "slow_api_threshold_ms": 200,
    "very_slow_api_threshold_ms": 500,
    "alert_threshold_ms": 1000,
    "sample_rate": 0.1
  }',
  'Thresholds for API performance monitoring'
)
ON CONFLICT (key) DO NOTHING;

INSERT INTO monitoring.config (key, value, description) VALUES
('caching_config', 
  '{
    "cache_ttl_seconds": 3600,
    "max_cache_size_mb": 100,
    "min_hit_rate_percent": 70
  }',
  'Configuration for caching system'
)
ON CONFLICT (key) DO NOTHING;

INSERT INTO monitoring.config (key, value, description) VALUES
('monitoring_retention', 
  '{
    "query_performance_days": 30,
    "memory_usage_days": 90,
    "api_performance_days": 30,
    "cache_stats_days": 14
  }',
  'Data retention periods for monitoring data'
)
ON CONFLICT (key) DO NOTHING;

-- Create a function to get configuration
CREATE OR REPLACE FUNCTION monitoring.get_config(p_key TEXT) 
RETURNS JSONB AS $$
BEGIN
  RETURN (SELECT value FROM monitoring.config WHERE key = p_key);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create a function to update configuration
CREATE OR REPLACE FUNCTION monitoring.update_config(p_key TEXT, p_value JSONB) 
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE monitoring.config 
  SET 
    value = p_value,
    updated_at = NOW(),
    updated_by = auth.uid()
  WHERE key = p_key;
  
  IF FOUND THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Apply RLS to config table
ALTER TABLE monitoring.config ENABLE ROW LEVEL SECURITY;

-- RLS policy for config table - only service_role can modify
CREATE POLICY "Admin can view and update config" ON monitoring.config
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Grant permissions
GRANT EXECUTE ON FUNCTION monitoring.get_config TO authenticated;
GRANT EXECUTE ON FUNCTION monitoring.update_config TO service_role;
