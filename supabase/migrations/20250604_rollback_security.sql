-- Rollback script for security changes
begin;
  -- 1. Disable RLS
  alter table users disable row level security;
  alter table playlists disable row level security;
  alter table playlist_songs disable row level security;
  alter table songs disable row level security;
  alter table artists disable row level security;
  alter table albums disable row level security;
  alter table user_preferences disable row level security;
  alter table user_activity_logs disable row level security;

  -- 2. Restore original policies from backup
  do $$
  declare
    pol record;
  begin
    for pol in select * from policy_backups order by created_at desc limit 1
    loop
      execute pol.policy_definition;
    end loop;
  end $$;

  -- 3. Clean up rate limiting
  drop function if exists check_rate_limit;
  drop index if exists idx_api_request_logs_user_endpoint_time;
  drop table if exists api_request_logs;
  drop table if exists api_rate_limits;
  drop table if exists policy_backups;
commit;
