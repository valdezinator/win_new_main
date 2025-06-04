-- Up Migration
-- Create content tables
create table if not exists artists (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  bio text,
  image_url text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists albums (
  id uuid primary key default uuid_generate_v4(),
  title text not null,
  artist_id uuid references artists not null,
  release_date date,
  cover_url text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists songs (
  id uuid primary key default uuid_generate_v4(),
  title text not null,
  album_id uuid references albums,
  artist_id uuid references artists not null,
  duration interval not null,
  track_number int,
  audio_url text not null,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists playlists (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users not null,
  name text not null,
  description text,
  is_public boolean default false,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists playlist_songs (
  id uuid primary key default uuid_generate_v4(),
  playlist_id uuid references playlists not null,
  song_id uuid references songs not null,
  position int not null,
  created_at timestamp with time zone default now(),
  unique(playlist_id, song_id),
  unique(playlist_id, position)
);

---- Down Migration
-- To revert, drop tables in correct order
/*
drop table if exists playlist_songs;
drop table if exists playlists;
drop table if exists songs;
drop table if exists albums;
drop table if exists artists;
*/
