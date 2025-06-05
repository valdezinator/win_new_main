/* 
 * Performance Monitoring Edge Function
 * This Edge Function serves as an endpoint for capturing performance metrics from the backend
 * operations. It allows the server to log performance data without affecting the frontend.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Create a Supabase client with the Admin key
const supabaseClient = createClient(
  // Supabase API URL - env var exported by default.
  Deno.env.get('SUPABASE_URL') ?? '',
  // Supabase API SERVICE ROLE KEY - env var exported by default.
  // WARNING: Never expose this in the browser.
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
)

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      },
    })
  }

  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get the request body
    const body = await req.json()
    const { 
      metric_type, 
      data
    } = body

    // Start timer for this function's performance tracking
    const startTime = performance.now()

    // Validate request
    if (!metric_type || !data) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    let result
    
    // Process different types of metrics
    switch (metric_type) {
      case 'query_performance':
        // Log query performance
        const { query_text, execution_time, rows_returned } = data
        
        if (!query_text || !execution_time) {
          return new Response(JSON.stringify({ error: 'Missing required fields for query_performance' }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' },
          })
        }
        
        const { data: queryData, error: queryError } = await supabaseClient
          .from('monitoring.query_performance')
          .insert({
            query_text,
            execution_time,
            rows_returned: rows_returned || 0,
            memory_usage: data.memory_usage || 0,
            user_id: data.user_id
          })
          .single()
          
        result = queryData
        if (queryError) throw queryError
        break
        
      case 'api_performance':
        // Log API performance
        const { path, method, status_code, response_time_ms } = data
        
        if (!path || !method || !response_time_ms) {
          return new Response(JSON.stringify({ error: 'Missing required fields for api_performance' }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' },
          })
        }
        
        const { data: apiData, error: apiError } = await supabaseClient.rpc(
          'monitoring.log_api_performance',
          {
            p_path: path,
            p_method: method,
            p_status_code: status_code || 200,
            p_response_time_ms: response_time_ms,
            p_request_payload: data.request_payload || null,
            p_client_info: data.client_info || null
          }
        )
        
        result = apiData
        if (apiError) throw apiError
        break
        
      case 'cache_stats':
        // Log cache statistics
        const { cache_key, is_hit } = data
        
        if (!cache_key || is_hit === undefined) {
          return new Response(JSON.stringify({ error: 'Missing required fields for cache_stats' }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' },
          })
        }
        
        const { error: cacheError } = await supabaseClient.rpc(
          'monitoring.update_cache_stats',
          {
            p_cache_key: cache_key,
            p_is_hit: is_hit,
            p_cache_size_bytes: data.cache_size_bytes || null
          }
        )
        
        if (cacheError) throw cacheError
        result = { success: true }
        break
        
      case 'run_maintenance':
        // Run monitoring maintenance tasks
        const { error: maintError } = await supabaseClient.rpc('monitoring.scheduled_monitoring')
        
        if (maintError) throw maintError
        result = { success: true }
        break
        
      case 'get_optimization_suggestions':
        // Get query optimization suggestions
        const { data: suggData, error: suggError } = await supabaseClient.rpc(
          'monitoring.suggest_query_optimization'
        )
        
        result = suggData
        if (suggError) throw suggError
        break
        
      default:
        return new Response(JSON.stringify({ error: 'Unknown metric type' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        })
    }

    // Track performance of this edge function itself
    const endTime = performance.now()
    const executionTime = endTime - startTime
    
    // Log the edge function's own performance (but don't wait for it)
    supabaseClient.rpc('monitoring.log_api_performance', {
      p_path: '/functions/v1/performance-monitoring',
      p_method: 'POST',
      p_status_code: 200,
      p_response_time_ms: executionTime,
      p_request_payload: { metric_type },
      p_client_info: { edge_function: true }
    }).then()

    return new Response(
      JSON.stringify({
        success: true,
        data: result,
        execution_time_ms: executionTime
      }),
      {
        headers: { 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error.message || 'Unknown error',
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})
