-- Add missing columns
alter table playlists add column if not exists is_public boolean default false;

-- Re-create RLS policies
drop policy if exists "Anyone can read public playlists" on playlists;
drop policy if exists "Users can CRUD their own playlists" on playlists;
drop policy if exists "Anyone can read songs from public playlists" on playlist_songs;
drop policy if exists "Users can manage songs in their playlists" on playlist_songs;

create policy "Anyone can read public playlists"
  on playlists for select
  using (is_public = true or auth.uid() = user_id);

create policy "Users can CRUD their own playlists"
  on playlists for all
  using (auth.uid() = user_id);

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
