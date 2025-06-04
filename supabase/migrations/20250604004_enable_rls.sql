-- Up Migration
-- Enable RLS and create policies
alter table users enable row level security;
alter table playlists enable row level security;
alter table playlist_songs enable row level security;
alter table songs enable row level security;
alter table artists enable row level security;
alter table albums enable row level security;
alter table user_preferences enable row level security;
alter table user_activity_logs enable row level security;

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
  with check (true);

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

---- Down Migration
-- To revert, drop policies and disable RLS
/*
-- Drop policies in reverse order
drop policy if exists "Public read access for artists" on artists;
drop policy if exists "Public read access for albums" on albums;
drop policy if exists "Public read access for songs" on songs;
drop policy if exists "System can write user activity" on user_activity_logs;
drop policy if exists "Users can read their own activity" on user_activity_logs;
drop policy if exists "Users can manage their preferences" on user_preferences;
drop policy if exists "Users can manage songs in their playlists" on playlist_songs;
drop policy if exists "Anyone can read songs from public playlists" on playlist_songs;
drop policy if exists "Users can CRUD their own playlists" on playlists;
drop policy if exists "Anyone can read public playlists" on playlists;
drop policy if exists "Users can update their own data" on users;
drop policy if exists "Users can read their own data" on users;

-- Disable RLS
alter table users disable row level security;
alter table playlists disable row level security;
alter table playlist_songs disable row level security;
alter table songs disable row level security;
alter table artists disable row level security;
alter table albums disable row level security;
alter table user_preferences disable row level security;
alter table user_activity_logs disable row level security;
*/
