-- Create user favorites table
CREATE TABLE IF NOT EXISTS user_favorites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  album_id UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, album_id)
);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_user_favorites_user_id ON user_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_user_favorites_album_id ON user_favorites(album_id);

-- Enable Row Level Security
ALTER TABLE user_favorites ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Users can manage their own favorites"
  ON user_favorites FOR ALL
  USING (auth.uid() = user_id);

-- Create a function to check if an album is favorited
CREATE OR REPLACE FUNCTION is_album_favorited(p_user_id UUID, p_album_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_favorites 
    WHERE user_id = p_user_id AND album_id = p_album_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a function to toggle album favorite status
CREATE OR REPLACE FUNCTION toggle_album_favorite(p_user_id UUID, p_album_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  is_favorited BOOLEAN;
BEGIN
  -- Check if already favorited
  SELECT EXISTS (
    SELECT 1 FROM user_favorites 
    WHERE user_id = p_user_id AND album_id = p_album_id
  ) INTO is_favorited;
  
  IF is_favorited THEN
    -- Remove from favorites
    DELETE FROM user_favorites 
    WHERE user_id = p_user_id AND album_id = p_album_id;
    RETURN FALSE;
  ELSE
    -- Add to favorites
    INSERT INTO user_favorites (user_id, album_id)
    VALUES (p_user_id, p_album_id);
    RETURN TRUE;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; 