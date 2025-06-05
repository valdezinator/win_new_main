-- Database Optimization Functions
-- This file contains functions to automatically optimize database performance

-- Create a function to identify and create missing indices
CREATE OR REPLACE FUNCTION monitoring.identify_missing_indices()
RETURNS TABLE(
  table_name TEXT,
  column_name TEXT,
  estimated_improvement FLOAT
) AS $$
BEGIN
  RETURN QUERY
  WITH slow_queries AS (
    SELECT
      query_text,
      AVG(execution_time) as avg_time
    FROM
      monitoring.query_performance
    GROUP BY
      query_text
    HAVING
      AVG(execution_time) > 100 -- queries taking more than 100ms
  ),
  query_columns AS (
    SELECT
      DISTINCT
      regexp_matches(lower(query_text), 'where\\s+([a-z0-9_]+)\\s*[=<>]', 'g') as col_match
    FROM
      slow_queries
  )
  SELECT
    t.tablename::TEXT as table_name,
    c.column_name::TEXT,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE
          schemaname = t.schemaname AND
          tablename = t.tablename AND
          indexdef LIKE '%' || c.column_name || '%'
      )
      THEN 0.0 -- index already exists
      ELSE
        -- Estimate improvement based on number of times column appears in slow queries
        (SELECT
          COUNT(*)::FLOAT / 10
         FROM
          query_columns qc
         WHERE
          qc.col_match[1] = c.column_name)
    END as estimated_improvement
  FROM
    pg_tables t
  JOIN
    information_schema.columns c
    ON t.schemaname = c.table_schema AND t.tablename = c.table_name
  WHERE
    t.schemaname NOT IN ('pg_catalog', 'information_schema', 'monitoring')
    AND c.column_name IN (
      SELECT DISTINCT col_match[1] FROM query_columns
    )
  ORDER BY
    estimated_improvement DESC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql;

-- Create a function to find tables that should be vacuumed
CREATE OR REPLACE FUNCTION monitoring.identify_vacuum_candidates()
RETURNS TABLE(
  table_name TEXT,
  dead_tuples BIGINT,
  live_tuples BIGINT,
  last_vacuum TIMESTAMPTZ,
  last_analyze TIMESTAMPTZ,
  recommended_action TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    stat.relname::TEXT AS table_name,
    stat.n_dead_tup AS dead_tuples,
    stat.n_live_tup AS live_tuples,
    stat.last_vacuum,
    stat.last_analyze,
    CASE
      WHEN stat.n_dead_tup > 10000 AND (stat.last_vacuum IS NULL OR stat.last_vacuum < NOW() - INTERVAL '7 days')
        THEN 'VACUUM'
      WHEN stat.n_live_tup > 10000 AND (stat.last_analyze IS NULL OR stat.last_analyze < NOW() - INTERVAL '7 days')
        THEN 'ANALYZE'
      WHEN stat.n_dead_tup > stat.n_live_tup / 2
        THEN 'VACUUM ANALYZE'
      ELSE
        'No action needed'
    END AS recommended_action
  FROM
    pg_stat_user_tables stat
  WHERE
    (stat.n_dead_tup > 1000 OR
    stat.n_live_tup > 10000 OR
    stat.last_vacuum IS NULL OR
    stat.last_analyze IS NULL)
  ORDER BY
    stat.n_dead_tup DESC;
END;
$$ LANGUAGE plpgsql;

-- Create a function to run optimization actions
CREATE OR REPLACE FUNCTION monitoring.optimize_database()
RETURNS TEXT AS $$
DECLARE
  v_table RECORD;
  v_index RECORD;
  v_result TEXT := '';
  v_count INT := 0;
BEGIN
  -- Find and vacuum tables that need it
  FOR v_table IN SELECT * FROM monitoring.identify_vacuum_candidates() LOOP
    IF v_table.recommended_action = 'VACUUM' THEN
      EXECUTE 'VACUUM ' || v_table.table_name;
      v_result := v_result || 'Vacuumed table: ' || v_table.table_name || E'\n';
      v_count := v_count + 1;
    ELSIF v_table.recommended_action = 'ANALYZE' THEN
      EXECUTE 'ANALYZE ' || v_table.table_name;
      v_result := v_result || 'Analyzed table: ' || v_table.table_name || E'\n';
      v_count := v_count + 1;
    ELSIF v_table.recommended_action = 'VACUUM ANALYZE' THEN
      EXECUTE 'VACUUM ANALYZE ' || v_table.table_name;
      v_result := v_result || 'Vacuumed and analyzed table: ' || v_table.table_name || E'\n';
      v_count := v_count + 1;
    END IF;
    
    -- Safety limit to avoid running too many operations at once
    EXIT WHEN v_count >= 5;
  END LOOP;

  -- Update optimization log
  INSERT INTO monitoring.optimization_log (
    action_type,
    details,
    success
  ) VALUES (
    'AUTOMATED_MAINTENANCE',
    v_result,
    TRUE
  );
  
  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  -- Log error
  INSERT INTO monitoring.optimization_log (
    action_type,
    details,
    success,
    error_message
  ) VALUES (
    'AUTOMATED_MAINTENANCE',
    v_result,
    FALSE,
    SQLERRM
  );
  
  RETURN 'Error: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Create a table to log optimization actions
CREATE TABLE IF NOT EXISTS monitoring.optimization_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action_type TEXT NOT NULL,
  details TEXT,
  success BOOLEAN DEFAULT TRUE,
  error_message TEXT,
  executed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create a function to fix a specific performance issue
CREATE OR REPLACE FUNCTION monitoring.fix_performance_issue(p_issue_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_issue RECORD;
  v_result TEXT;
BEGIN
  -- Get the issue details
  SELECT * INTO v_issue 
  FROM monitoring.query_performance 
  WHERE id = p_issue_id;

  IF NOT FOUND THEN
    RETURN 'Issue not found';
  END IF;

  -- Analyze the issue type and apply fixes
  IF v_issue.execution_time > 1000 THEN
    -- For extremely slow queries, try to create indices based on WHERE clauses
    -- Extract table and column names from query (simplified approach)
    DECLARE
      v_table_name TEXT;
      v_column_name TEXT;
    BEGIN
      -- Very basic extraction - in real world use a more sophisticated approach
      v_table_name := (SELECT substring(v_issue.query_text FROM 'FROM\s+([a-zA-Z0-9_\.]+)'));
      v_column_name := (SELECT substring(v_issue.query_text FROM 'WHERE\s+([a-zA-Z0-9_\.]+)\s*='));
      
      IF v_table_name IS NOT NULL AND v_column_name IS NOT NULL THEN
        -- Try to create an index
        BEGIN
          EXECUTE 'CREATE INDEX IF NOT EXISTS idx_auto_' || 
            replace(v_column_name, '.', '_') || 
            ' ON ' || v_table_name || ' (' || v_column_name || ')';
          
          v_result := 'Created index on ' || v_table_name || '.' || v_column_name;
        EXCEPTION WHEN OTHERS THEN
          v_result := 'Failed to create index: ' || SQLERRM;
        END;
      ELSE
        v_result := 'Could not extract table and column names from query';
      END IF;
    END;
  ELSE
    -- For moderately slow queries, suggest EXPLAIN ANALYZE
    v_result := 'Suggested action: Run EXPLAIN ANALYZE on this query to identify bottlenecks';
  END IF;

  -- Log the action
  INSERT INTO monitoring.optimization_log (
    action_type,
    details,
    success
  ) VALUES (
    'MANUAL_OPTIMIZATION',
    'Issue ID: ' || p_issue_id || ', Action: ' || v_result,
    TRUE
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Apply RLS to the optimization log
ALTER TABLE monitoring.optimization_log ENABLE ROW LEVEL SECURITY;

-- Set RLS policy
CREATE POLICY "Admin can view optimization log" ON monitoring.optimization_log
  FOR SELECT USING (auth.role() = 'service_role');

CREATE POLICY "Service role can insert into optimization log" ON monitoring.optimization_log
  FOR INSERT WITH CHECK (auth.role() = 'service_role');

-- Grant permissions
GRANT EXECUTE ON FUNCTION monitoring.identify_missing_indices TO service_role;
GRANT EXECUTE ON FUNCTION monitoring.identify_vacuum_candidates TO service_role;
GRANT EXECUTE ON FUNCTION monitoring.optimize_database TO service_role;
GRANT EXECUTE ON FUNCTION monitoring.fix_performance_issue TO service_role;
