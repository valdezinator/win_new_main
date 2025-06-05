-- Enable required PostgreSQL extensions for performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create a schema for performance monitoring
CREATE SCHEMA IF NOT EXISTS monitoring;

-- Create a table to track query performance
CREATE TABLE IF NOT EXISTS monitoring.query_performance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  query_text TEXT NOT NULL,
  execution_time FLOAT NOT NULL,
  rows_returned INTEGER,
  memory_usage INTEGER,
  called_at TIMESTAMPTZ DEFAULT NOW(),
  user_id UUID
);

-- Create a table for tracking memory usage
CREATE TABLE IF NOT EXISTS monitoring.memory_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create a table for tracking API performance
CREATE TABLE IF NOT EXISTS monitoring.api_performance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  path TEXT NOT NULL,
  method TEXT NOT NULL,
  status_code INTEGER,
  response_time_ms FLOAT NOT NULL,
  request_payload JSONB,
  user_id UUID,
  client_info JSONB,
  called_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create a table for tracking cache stats
CREATE TABLE IF NOT EXISTS monitoring.cache_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cache_key TEXT NOT NULL,
  hit_count INTEGER DEFAULT 0,
  miss_count INTEGER DEFAULT 0,
  cache_size_bytes INTEGER,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create a table for potential memory leaks tracking
CREATE TABLE IF NOT EXISTS monitoring.memory_leak_candidates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_name TEXT NOT NULL,
  allocation_size BIGINT NOT NULL,
  allocation_count INTEGER NOT NULL,
  deallocation_count INTEGER NOT NULL,
  detected_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create a function to track expensive queries
CREATE OR REPLACE FUNCTION monitoring.track_query_performance() RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'DELETE') THEN
    RETURN OLD;
  END IF;
  
  -- Only track queries that take longer than 100ms
  IF NEW.total_exec_time / 1000 > 100 THEN
    INSERT INTO monitoring.query_performance (
      query_text,
      execution_time,
      rows_returned,
      memory_usage,
      user_id
    ) VALUES (
      NEW.query,
      NEW.total_exec_time / 1000, -- convert to milliseconds
      NEW.rows,
      NEW.shared_blks_hit + NEW.shared_blks_read,
      current_setting('auth.uid', TRUE)::uuid
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create a function to capture and analyze database stats
CREATE OR REPLACE FUNCTION monitoring.capture_db_stats() RETURNS VOID AS $$
BEGIN
  -- Capture table sizes
  INSERT INTO monitoring.memory_usage (table_name, size_bytes)
  SELECT 
    table_name,
    pg_total_relation_size(table_name::regclass) AS size_bytes
  FROM 
    information_schema.tables
  WHERE 
    table_schema NOT IN ('pg_catalog', 'information_schema', 'monitoring')
    AND table_type = 'BASE TABLE';

  -- Look for potential memory leaks
  INSERT INTO monitoring.memory_leak_candidates (
    resource_name, 
    allocation_size, 
    allocation_count, 
    deallocation_count
  )
  SELECT 
    query AS resource_name,
    mean_exec_time AS allocation_size,
    calls AS allocation_count,
    calls - 1 AS deallocation_count
  FROM 
    pg_stat_statements
  WHERE
    mean_exec_time > 1000 -- queries taking more than 1 second
    AND calls > 10 -- called multiple times
  ORDER BY 
    mean_exec_time DESC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql;

-- Create a function to log API performance
CREATE OR REPLACE FUNCTION monitoring.log_api_performance(
  p_path TEXT,
  p_method TEXT,
  p_status_code INTEGER,
  p_response_time_ms FLOAT,
  p_request_payload JSONB DEFAULT NULL,
  p_client_info JSONB DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  v_user_id UUID;
  v_log_id UUID;
BEGIN
  -- Try to get authenticated user
  BEGIN
    v_user_id := auth.uid();
  EXCEPTION WHEN OTHERS THEN
    v_user_id := NULL;
  END;

  INSERT INTO monitoring.api_performance (
    path,
    method,
    status_code,
    response_time_ms,
    request_payload,
    user_id,
    client_info
  ) VALUES (
    p_path,
    p_method,
    p_status_code,
    p_response_time_ms,
    p_request_payload,
    v_user_id,
    p_client_info
  ) RETURNING id INTO v_log_id;
  
  RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

-- Create a function to update cache statistics
CREATE OR REPLACE FUNCTION monitoring.update_cache_stats(
  p_cache_key TEXT,
  p_is_hit BOOLEAN,
  p_cache_size_bytes INTEGER DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  INSERT INTO monitoring.cache_stats (
    cache_key,
    hit_count,
    miss_count,
    cache_size_bytes
  ) VALUES (
    p_cache_key,
    CASE WHEN p_is_hit THEN 1 ELSE 0 END,
    CASE WHEN p_is_hit THEN 0 ELSE 1 END,
    p_cache_size_bytes
  )
  ON CONFLICT (cache_key) DO UPDATE SET
    hit_count = monitoring.cache_stats.hit_count + CASE WHEN p_is_hit THEN 1 ELSE 0 END,
    miss_count = monitoring.cache_stats.miss_count + CASE WHEN p_is_hit THEN 0 ELSE 1 END,
    cache_size_bytes = COALESCE(p_cache_size_bytes, monitoring.cache_stats.cache_size_bytes),
    recorded_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- Create views for monitoring
CREATE OR REPLACE VIEW monitoring.slow_queries AS
SELECT 
  query_text, 
  AVG(execution_time) as avg_execution_time,
  MAX(execution_time) as max_execution_time,
  MIN(execution_time) as min_execution_time,
  COUNT(*) as call_count,
  SUM(rows_returned) as total_rows_returned
FROM 
  monitoring.query_performance
GROUP BY 
  query_text
ORDER BY 
  avg_execution_time DESC;

CREATE OR REPLACE VIEW monitoring.memory_usage_trends AS
SELECT 
  table_name,
  recorded_at::date as day,
  MAX(size_bytes) as peak_size_bytes,
  MIN(size_bytes) as min_size_bytes,
  AVG(size_bytes) as avg_size_bytes
FROM 
  monitoring.memory_usage
GROUP BY 
  table_name, recorded_at::date
ORDER BY 
  day DESC, peak_size_bytes DESC;

CREATE OR REPLACE VIEW monitoring.api_performance_summary AS
SELECT 
  path,
  method,
  AVG(response_time_ms) as avg_response_time,
  MAX(response_time_ms) as max_response_time,
  MIN(response_time_ms) as min_response_time,
  COUNT(*) as call_count,
  COUNT(DISTINCT user_id) as unique_users
FROM 
  monitoring.api_performance
GROUP BY 
  path, method
ORDER BY 
  avg_response_time DESC;

-- Create a scheduled function to run monitoring tasks (will run every hour)
CREATE OR REPLACE FUNCTION monitoring.scheduled_monitoring() RETURNS VOID AS $$
BEGIN
  -- Capture database stats
  PERFORM monitoring.capture_db_stats();
  
  -- Reset pg_stat_statements to avoid excess growth
  PERFORM pg_stat_statements_reset();
  
  -- Clean up old monitoring data (keep 30 days of history)
  DELETE FROM monitoring.query_performance WHERE called_at < NOW() - INTERVAL '30 days';
  DELETE FROM monitoring.memory_usage WHERE recorded_at < NOW() - INTERVAL '30 days';
  DELETE FROM monitoring.api_performance WHERE called_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- Create RLS policies to protect monitoring data
ALTER TABLE monitoring.query_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitoring.memory_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitoring.api_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitoring.cache_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitoring.memory_leak_candidates ENABLE ROW LEVEL SECURITY;

-- Only allow admins to view monitoring data
CREATE POLICY "Admin can view monitoring data" ON monitoring.query_performance
  FOR SELECT USING (auth.role() = 'service_role');

CREATE POLICY "Admin can view memory usage" ON monitoring.memory_usage
  FOR SELECT USING (auth.role() = 'service_role');

CREATE POLICY "Admin can view API performance" ON monitoring.api_performance
  FOR SELECT USING (auth.role() = 'service_role');

CREATE POLICY "Admin can view cache stats" ON monitoring.cache_stats
  FOR SELECT USING (auth.role() = 'service_role');

CREATE POLICY "Admin can view memory leak candidates" ON monitoring.memory_leak_candidates
  FOR SELECT USING (auth.role() = 'service_role');

-- Create indices for better query performance
CREATE INDEX idx_query_performance_execution_time ON monitoring.query_performance(execution_time);
CREATE INDEX idx_query_performance_called_at ON monitoring.query_performance(called_at);
CREATE INDEX idx_memory_usage_recorded_at ON monitoring.memory_usage(recorded_at);
CREATE INDEX idx_api_performance_response_time ON monitoring.api_performance(response_time_ms);
CREATE INDEX idx_api_performance_path ON monitoring.api_performance(path);
CREATE INDEX idx_api_performance_called_at ON monitoring.api_performance(called_at);

-- Create a function for automatically optimizing queries
CREATE OR REPLACE FUNCTION monitoring.suggest_query_optimization() RETURNS TABLE(
  query_text TEXT,
  avg_execution_time FLOAT,
  call_count BIGINT,
  suggested_optimization TEXT
) AS $$
BEGIN
  RETURN QUERY
  WITH slow_queries AS (
    SELECT 
      query_text, 
      AVG(execution_time) as avg_time,
      COUNT(*) as calls
    FROM 
      monitoring.query_performance
    GROUP BY 
      query_text
    HAVING 
      AVG(execution_time) > 500 -- queries taking more than 500ms
    ORDER BY 
      AVG(execution_time) DESC
    LIMIT 20
  )
  SELECT 
    sq.query_text,
    sq.avg_time,
    sq.calls,
    CASE 
      WHEN sq.query_text ~* 'SELECT.*FROM.*WHERE' AND sq.query_text !~* 'EXPLAIN' THEN 
        'Consider adding indexes for WHERE clause columns or use EXPLAIN ANALYZE to identify bottlenecks'
      WHEN sq.query_text ~* 'JOIN' AND sq.query_text !~* 'EXPLAIN' THEN
        'Consider optimizing JOIN conditions or adding indexes on JOIN columns'
      WHEN sq.query_text ~* 'GROUP BY' AND sq.query_text !~* 'EXPLAIN' THEN
        'Consider adding indexes for GROUP BY columns'
      WHEN sq.query_text ~* 'ORDER BY' AND sq.query_text !~* 'EXPLAIN' THEN
        'Consider adding indexes for ORDER BY columns'
      ELSE
        'Run EXPLAIN ANALYZE on this query to identify specific optimizations'
    END as suggested_optimization
  FROM 
    slow_queries sq;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions to use the monitoring functions to authenticated users
GRANT USAGE ON SCHEMA monitoring TO authenticated;
GRANT EXECUTE ON FUNCTION monitoring.log_api_performance TO authenticated;
GRANT EXECUTE ON FUNCTION monitoring.update_cache_stats TO authenticated;

-- Grant permissions to service role for all monitoring functions
GRANT ALL ON SCHEMA monitoring TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA monitoring TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA monitoring TO service_role;

COMMENT ON SCHEMA monitoring IS 'Schema for performance monitoring and profiling';
COMMENT ON TABLE monitoring.query_performance IS 'Tracks performance of expensive database queries';
COMMENT ON TABLE monitoring.memory_usage IS 'Tracks memory usage of database tables';
COMMENT ON TABLE monitoring.api_performance IS 'Tracks performance of API calls';
COMMENT ON TABLE monitoring.cache_stats IS 'Tracks cache hit/miss rates';
COMMENT ON TABLE monitoring.memory_leak_candidates IS 'Identifies potential memory leaks';
