-- Up Migration
-- Create security tables and functions
create table if not exists api_request_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id),
  endpoint text not null,
  method text not null,
  status_code int,
  response_time_ms int,
  created_at timestamp with time zone default now(),
  ip_address inet,
  user_agent text
);

create table if not exists api_keys (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) not null,
  key_hash text not null,
  created_at timestamp with time zone default now(),
  expires_at timestamp with time zone default now() + interval '30 days',
  is_active boolean default true,
  last_used timestamp with time zone,
  last_rotated timestamp with time zone default now()
);

-- Create rate limiting function
create or replace function check_rate_limit(
  p_user_id uuid,
  p_endpoint text,
  p_limit int default 100,
  p_window interval default interval '1 hour'
) returns boolean as $$
declare
  request_count int;
begin
  select count(*)
  into request_count
  from api_request_logs
  where user_id = p_user_id
    and endpoint = p_endpoint
    and created_at > now() - p_window;
    
  return request_count < p_limit;
end;
$$ language plpgsql security definer;

-- Function to rotate API keys
create or replace function rotate_api_key(
  p_user_id uuid,
  p_old_key_hash text
) returns uuid as $$
declare
  new_key_id uuid;
begin
  update api_keys
  set is_active = false
  where user_id = p_user_id
    and key_hash = p_old_key_hash
    and is_active = true;
    
  insert into api_keys (user_id, key_hash, expires_at)
  values (p_user_id, gen_random_uuid()::text, now() + interval '30 days')
  returning id into new_key_id;
  
  return new_key_id;
end;
$$ language plpgsql security definer;

-- Create index for rate limiting queries
create index idx_api_request_logs_user_endpoint_time
  on api_request_logs (user_id, endpoint, created_at);

-- Create index for API key lookups
create index idx_api_keys_user_hash
  on api_keys (user_id, key_hash)
  where is_active = true;

---- Down Migration
-- To revert, drop functions and tables in correct order
/*
drop function if exists rotate_api_key;
drop function if exists check_rate_limit;
drop table if exists api_keys;
drop table if exists api_request_logs;
*/
