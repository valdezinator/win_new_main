-- Create the dynamic_playlists table
CREATE TABLE IF NOT EXISTS dynamic_playlists (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  playlist_type VARCHAR NOT NULL,
  name VARCHAR NOT NULL,
  description TEXT,
  image_url TEXT,
  metadata JSONB,
  last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create the dynamic_playlist_songs junction table
CREATE TABLE IF NOT EXISTS dynamic_playlist_songs (
  playlist_id UUID REFERENCES dynamic_playlists(id) ON DELETE CASCADE,
  song_id UUID REFERENCES songs(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (playlist_id, song_id)
);

-- Create function to generate the daylist
CREATE OR REPLACE FUNCTION generate_daylist(user_uuid UUID, current_hour INTEGER)
RETURNS SETOF dynamic_playlists AS $$
DECLARE
  new_playlist_id UUID;
  time_of_day TEXT;
  playlist_mood TEXT;
BEGIN
  -- Determine time of day and mood
  time_of_day := CASE 
    WHEN current_hour BETWEEN 5 AND 11 THEN 'Morning'
    WHEN current_hour BETWEEN 12 AND 16 THEN 'Afternoon'
    WHEN current_hour BETWEEN 17 AND 20 THEN 'Evening'
    ELSE 'Night'
  END;
  
  playlist_mood := CASE 
    WHEN time_of_day = 'Morning' THEN 'energetic'
    WHEN time_of_day = 'Afternoon' THEN 'focused'
    WHEN time_of_day = 'Evening' THEN 'relaxed'
    ELSE 'chill'
  END;

  -- Create or update daylist
  INSERT INTO dynamic_playlists (
    user_id,
    playlist_type,
    name,
    description,
    metadata
  )
  VALUES (
    user_uuid,
    'daylist',
    time_of_day || ' Mix',
    'Your personalized mix for ' || time_of_day || ' vibes',
    jsonb_build_object(
      'time_of_day', time_of_day,
      'mood', playlist_mood
    )
  )
  ON CONFLICT (user_id, playlist_type) 
  WHERE playlist_type = 'daylist'
  DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    metadata = EXCLUDED.metadata,
    last_updated = NOW()
  RETURNING id INTO new_playlist_id;

  -- Clear existing songs for this playlist
  DELETE FROM dynamic_playlist_songs WHERE playlist_id = new_playlist_id;

  -- Insert new songs based on mood
  INSERT INTO dynamic_playlist_songs (playlist_id, song_id, position)
  SELECT 
    new_playlist_id,
    s.id,
    ROW_NUMBER() OVER (ORDER BY RANDOM())
  FROM songs s
  WHERE s.genre && ARRAY[playlist_mood]::varchar[]
  ORDER BY RANDOM()
  LIMIT 20;

  RETURN QUERY
  SELECT * FROM dynamic_playlists WHERE id = new_playlist_id;
END;
$$ LANGUAGE plpgsql;

-- Create function to generate the rewind playlist
CREATE OR REPLACE FUNCTION generate_rewind(user_uuid UUID)
RETURNS SETOF dynamic_playlists AS $$
DECLARE
  new_playlist_id UUID;
BEGIN
  -- Create or update rewind playlist
  INSERT INTO dynamic_playlists (
    user_id,
    playlist_type,
    name,
    description,
    metadata
  )
  VALUES (
    user_uuid,
    'rewind',
    'Your Weekly Rewind',
    'Rediscover your most played tracks from the past week',
    jsonb_build_object(
      'type', 'weekly_rewind',
      'week', EXTRACT(WEEK FROM NOW())::TEXT || '-' || EXTRACT(YEAR FROM NOW())::TEXT
    )
  )
  ON CONFLICT (user_id, playlist_type) 
  WHERE playlist_type = 'rewind'
  DO UPDATE SET
    last_updated = NOW()
  RETURNING id INTO new_playlist_id;

  -- Clear existing songs for this playlist
  DELETE FROM dynamic_playlist_songs WHERE playlist_id = new_playlist_id;

  -- Insert most played songs from the past week
  INSERT INTO dynamic_playlist_songs (playlist_id, song_id, position)
  SELECT 
    new_playlist_id,
    s.id,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) as position
  FROM play_history ph
  JOIN songs s ON s.id = ph.song_id
  WHERE 
    ph.user_id = user_uuid
    AND ph.played_at >= NOW() - INTERVAL '7 days'
  GROUP BY s.id
  ORDER BY COUNT(*) DESC
  LIMIT 30;

  RETURN QUERY
  SELECT * FROM dynamic_playlists WHERE id = new_playlist_id;
END;
$$ LANGUAGE plpgsql;

-- Add the necessary indexes
CREATE INDEX IF NOT EXISTS idx_dynamic_playlists_user_type 
  ON dynamic_playlists (user_id, playlist_type);

CREATE INDEX IF NOT EXISTS idx_dynamic_playlist_songs_playlist 
  ON dynamic_playlist_songs (playlist_id);

CREATE INDEX IF NOT EXISTS idx_dynamic_playlist_songs_song 
  ON dynamic_playlist_songs (song_id);
