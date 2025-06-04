-- Enable Row Level Security for all tables
alter table users enable row level security;
alter table playlists enable row level security;
alter table playlist_songs enable row level security;
alter table songs enable row level security;
alter table artists enable row level security;
alter table albums enable row level security;
alter table user_preferences enable row level security;
alter table user_activity_logs enable row level security;

-- Create an API request logging table
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

-- Create rate limiting function
create or replace function check_rate_limit(
  p_user_id uuid,
  p_endpoint text,
  p_limit int default 100,  -- Default 100 requests
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

-- Create API key rotation system
create table if not exists api_keys (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) not null,
  key_hash text not null,
  created_at timestamp with time zone default now(),
  expires_at timestamp with time zone not null,
  is_active boolean default true,
  last_used timestamp with time zone,
  last_rotated timestamp with time zone default now()
);

-- Function to rotate API keys
create or replace function rotate_api_key(
  p_user_id uuid,
  p_old_key_hash text
) returns uuid as $$
declare
  new_key_id uuid;
begin
  -- Deactivate old key
  update api_keys
  set is_active = false
  where user_id = p_user_id
    and key_hash = p_old_key_hash
    and is_active = true;
    
  -- Create new key
  insert into api_keys (user_id, key_hash, expires_at)
  values (p_user_id, gen_random_uuid()::text, now() + interval '30 days')
  returning id into new_key_id;
  
  return new_key_id;
end;
$$ language plpgsql security definer;

-- Users table RLS policies
create policy "Users can read their own data"
  on users for select
  using (auth.uid() = id);

create policy "Users can update their own data"
  on users for update
  using (auth.uid() = id);

-- Playlists RLS policies
create policy "Anyone can read public playlists"
  on playlists for select
  using (is_public = true or auth.uid() = user_id);

create policy "Users can CRUD their own playlists"
  on playlists for all
  using (auth.uid() = user_id);

-- Playlist songs RLS policies
create policy "Anyone can read songs from public playlists"
  on playlist_songs for select
  using (
    exists (
      select 1 from playlists
      where id = playlist_id
      and (is_public = true or user_id = auth.uid())
    )
  );

create policy "Users can manage songs in their playlists"
  on playlist_songs for all
  using (
    exists (
      select 1 from playlists
      where id = playlist_id and user_id = auth.uid()
    )
  );

-- User preferences RLS policies
create policy "Users can manage their preferences"
  on user_preferences for all
  using (auth.uid() = user_id);

-- User activity logs RLS policies
create policy "Users can read their own activity"
  on user_activity_logs for select
  using (auth.uid() = user_id);

create policy "System can write user activity"
  on user_activity_logs for insert
  with check (true);  -- Controlled through application logic

-- Songs and Albums - public read access
create policy "Public read access for songs"
  on songs for select
  using (true);

create policy "Public read access for albums"
  on albums for select
  using (true);

create policy "Public read access for artists"
  on artists for select
  using (true);

-- Create request validation trigger function
create or replace function validate_request()
returns trigger as $$
begin
  -- Validate user exists and is active
  if not exists (
    select 1 from auth.users
    where id = auth.uid()
    and confirmed_at is not null
    and banned_until is null
  ) then
    raise exception 'Invalid or inactive user';
  end if;
  
  -- Check rate limits
  if not check_rate_limit(auth.uid(), tg_table_name::text) then
    raise exception 'Rate limit exceeded';
  end if;
  
  -- Log the request
  insert into api_request_logs (
    user_id,
    endpoint,
    method,
    ip_address
  ) values (
    auth.uid(),
    tg_table_name::text,
    tg_op,
    inet_client_addr()
  );
  
  return new;
end;
$$ language plpgsql security definer;

-- Apply validation trigger to relevant tables
create trigger validate_playlist_request
  before insert or update or delete
  on playlists
  for each row
  execute function validate_request();

create trigger validate_playlist_songs_request
  before insert or update or delete
  on playlist_songs
  for each row
  execute function validate_request();

-- Create index for rate limiting queries
create index idx_api_request_logs_user_endpoint_time
  on api_request_logs (user_id, endpoint, created_at);

-- Create index for API key lookups
create index idx_api_keys_user_hash
  on api_keys (user_id, key_hash)
  where is_active = true;

-- Set up automatic key rotation
create or replace function auto_rotate_expired_keys()
returns void as $$
begin
  -- Deactivate expired keys
  update api_keys
  set is_active = false
  where expires_at < now()
    and is_active = true;
    
  -- Create new keys for recently expired ones
  insert into api_keys (user_id, key_hash, expires_at)
  select user_id, gen_random_uuid()::text, now() + interval '30 days'
  from api_keys
  where expires_at < now()
    and expires_at > now() - interval '1 day'
    and is_active = false;
end;
$$ language plpgsql security definer;

-- Create a scheduled job for key rotation
select cron.schedule(
  'rotate-expired-api-keys',
  '0 0 * * *',  -- Run daily at midnight
  $$
    select auto_rotate_expired_keys();
  $$
);
