-- Enable RLS if not already enabled for playlist_songs
alter table playlist_songs enable row level security;

-- Create policy to allow playlist owners to insert into playlist_songs
create policy "Allow insert for playlist owner" 
on playlist_songs
for insert
with check (
  auth.uid() = (
    select user_id from playlist where id = playlist_id
  )
);
