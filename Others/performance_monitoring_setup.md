# Performance Monitoring System Setup Guide

This guide explains how to set up the backend performance monitoring system for the Music Streaming App.

## Overview

The performance monitoring system consists of:

1. PostgreSQL extensions for query performance tracking
2. Database tables and functions for monitoring
3. Edge Functions for processing performance data
4. Automatic optimization tools
5. Image optimization service

## Installation Instructions

### 1. Apply Database Migrations

Run the following migrations in order:

```bash
# Deploy the performance monitoring tables and functions
supabase db push --db-url=<your-supabase-url>
```

This will deploy the following migrations:
- `20250604081234_add_performance_monitoring.sql` - Core monitoring tables and functions
- `20250604081235_add_performance_config.sql` - Monitoring configuration
- `20250604081236_add_database_optimization.sql` - DB optimization tools

### 2. Deploy Edge Functions

```bash
# Deploy the performance monitoring Edge Function
supabase functions deploy performance-monitoring --project-ref=<your-project-ref>

# Deploy the cron job function
supabase functions deploy performance-cron --project-ref=<your-project-ref>

# Deploy image processor
supabase functions deploy image-processor --project-ref=<your-project-ref>
```

### 3. Set Up Cron Job

Set up a cron job to run the performance maintenance tasks daily:

1. Go to your Supabase dashboard
2. Navigate to Database → Functions → Hooks
3. Create a new hook:
   - Schedule: `0 3 * * *` (runs at 3 AM daily)
   - HTTP Method: POST
   - URL: `https://<your-project-ref>.supabase.co/functions/v1/performance-cron`
   - Headers: 
     - `Authorization: Bearer <service-role-key>`
     - `Content-Type: application/json`

## Usage

### Monitoring Database Performance

You can view performance metrics by querying the monitoring tables:

```sql
-- View slow queries
SELECT * FROM monitoring.slow_queries LIMIT 10;

-- View API performance
SELECT * FROM monitoring.api_performance_summary LIMIT 10;

-- Check for memory leak candidates
SELECT * FROM monitoring.memory_leak_candidates LIMIT 10;
```

### Manually Optimize Database

If needed, you can manually trigger the optimization:

```sql
-- Run database optimization
SELECT monitoring.optimize_database();

-- Get optimization suggestions
SELECT * FROM monitoring.suggest_query_optimization();
```

### Using the Image Processor

To optimize images, use the image processor edge function:

```
GET: https://<your-project-ref>.supabase.co/functions/v1/image-processor?bucket=images&path=example.jpg&width=800&height=600&quality=80&format=webp
```

For batch optimization, use a POST request with a JSON body:

```json
{
  "bucket": "images",
  "files": ["image1.jpg", "image2.png"],
  "options": {
    "resize": { "width": 800 },
    "compress": { "quality": 80 },
    "format": "webp"
  }
}
```

## Maintenance

The system is designed to be largely self-maintaining, with the daily cron job handling routine tasks. However, you should occasionally:

1. Check the `monitoring.optimization_log` table for any errors
2. Review the optimization suggestions from `monitoring.suggest_query_optimization()`
3. Adjust the configuration values in the `monitoring.config` table if needed

## Configuration

You can adjust monitoring thresholds by modifying the configuration:

```sql
-- Update slow query threshold to 300ms
SELECT monitoring.update_config(
  'query_performance_thresholds',
  jsonb_build_object(
    'slow_query_threshold_ms', 300,
    'very_slow_query_threshold_ms', 1000,
    'alert_threshold_ms', 2000,
    'log_all_queries', false,
    'sample_rate', 0.1
  )
);
```

## Troubleshooting

If you encounter issues with the performance monitoring system:

1. Check the logs for the edge functions in the Supabase dashboard
2. Verify that the cron job is running correctly
3. Check for errors in the `monitoring.optimization_log` table
4. Make sure the PostgreSQL extensions are properly installed

For assistance, contact the system administrator.

## Security Considerations

- The monitoring data is protected by Row Level Security (RLS) policies
- Only users with the `service_role` can access the full monitoring data
- Regular users can log performance data but cannot read sensitive information

This ensures that performance monitoring doesn't expose any sensitive data.
