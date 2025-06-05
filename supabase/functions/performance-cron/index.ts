/* 
 * Performance Management Cron Job
 * This Edge Function runs on a schedule to perform database optimization and monitoring tasks
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

// This Edge Function is designed to run on a schedule
serve(async (req) => {
  try {
    console.log('Running scheduled performance maintenance tasks...')
    
    // Run the scheduled monitoring tasks
    const { data: monitoringData, error: monitoringError } = await supabaseClient.rpc('monitoring.scheduled_monitoring')
    
    if (monitoringError) {
      console.error('Error running scheduled monitoring:', monitoringError)
      throw monitoringError
    }
    
    console.log('Scheduled monitoring completed')
    
    // Run database optimization (every Sunday)
    const today = new Date()
    if (today.getDay() === 0) { // Sunday
      console.log('Running weekly database optimization...')
      
      const { data: optimizationData, error: optimizationError } = await supabaseClient.rpc('monitoring.optimize_database')
      
      if (optimizationError) {
        console.error('Error optimizing database:', optimizationError)
        throw optimizationError
      }
      
      console.log('Database optimization results:', optimizationData)
    }
    
    // Check for potential memory leaks
    const { data: leakData, error: leakError } = await supabaseClient
      .from('monitoring.memory_leak_candidates')
      .select('*')
      .order('detected_at', { ascending: false })
      .limit(10)
    
    if (leakError) {
      console.error('Error checking for memory leaks:', leakError)
      throw leakError
    }
    
    console.log(`Found ${leakData?.length || 0} potential memory leak candidates`)
      // Clean up old monitoring data based on retention policy
    const { data: retentionConfig, error: configError } = await supabaseClient.rpc(
      'monitoring.get_config',
      { key: 'monitoring_retention' }
    )
    
    if (configError) {
      console.error('Error fetching retention config:', configError)
      throw configError
    }
    
    // Apply retention policy
    if (retentionConfig) {
      const queries = [
        `DELETE FROM monitoring.query_performance WHERE called_at < NOW() - INTERVAL '${retentionConfig.query_performance_days} days'`,
        `DELETE FROM monitoring.memory_usage WHERE recorded_at < NOW() - INTERVAL '${retentionConfig.memory_usage_days} days'`,
        `DELETE FROM monitoring.api_performance WHERE called_at < NOW() - INTERVAL '${retentionConfig.api_performance_days} days'`,
        `DELETE FROM monitoring.cache_stats WHERE recorded_at < NOW() - INTERVAL '${retentionConfig.cache_stats_days} days'`,
      ]
        for (const query of queries) {
        try {
          const { data, error: deleteError } = await supabaseClient.rpc(
            'supabase_execute_sql', 
            { sql: query }
          )
          
          if (deleteError) {
            console.error('Error cleaning up old monitoring data:', deleteError)
          }
        } catch (queryError) {
          console.error('Error executing cleanup query:', queryError.message)
        }
        
        if (deleteError) {
          console.error('Error cleaning up old monitoring data:', deleteError)
        }
      }
      
      console.log('Applied retention policies for monitoring data')
    }
    
    // Generate optimization suggestions report
    const { data: suggestionData, error: suggestionError } = await supabaseClient.rpc(
      'monitoring.suggest_query_optimization'
    )
    
    if (suggestionError) {
      console.error('Error generating optimization suggestions:', suggestionError)
      throw suggestionError
    }
    
    // Log successful execution
    await supabaseClient
      .from('monitoring.optimization_log')
      .insert({
        action_type: 'SCHEDULED_CRON',
        details: `Completed successfully. Found ${leakData?.length || 0} potential leaks and ${suggestionData?.length || 0} optimization suggestions.`,
        success: true
      })

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Performance maintenance completed successfully',
        optimizationSuggestions: suggestionData?.length || 0,
        potentialMemoryLeaks: leakData?.length || 0
      }),
      {
        headers: { 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    // Log the error
    await supabaseClient
      .from('monitoring.optimization_log')
      .insert({
        action_type: 'SCHEDULED_CRON',
        details: 'Failed to run scheduled tasks',
        success: false,
        error_message: error.message
      })
    
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
