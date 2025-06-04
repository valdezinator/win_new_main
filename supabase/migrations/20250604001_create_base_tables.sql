-- Up Migration
-- Create required tables
create table if not exists users (
  id uuid references auth.users primary key,
  username text unique not null,
  display_name text,
  bio text,
  avatar_url text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists user_preferences (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users not null,
  theme text default 'light',
  language text default 'en',
  notifications_enabled boolean default true,
  audio_quality text default 'high',
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists user_activity_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users not null,
  activity_type text not null,
  details jsonb,
  created_at timestamp with time zone default now()
);

---- Down Migration
-- To revert, drop tables in correct order
/*
drop table if exists user_activity_logs;
drop table if exists user_preferences;
drop table if exists users;
*/
