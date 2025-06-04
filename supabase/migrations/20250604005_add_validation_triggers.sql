-- Up Migration
-- Create request validation trigger
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

-- Apply validation trigger to tables
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

---- Down Migration
-- To revert, drop triggers and function
/*
drop trigger if exists validate_playlist_songs_request on playlist_songs;
drop trigger if exists validate_playlist_request on playlists;
drop function if exists validate_request;
*/
