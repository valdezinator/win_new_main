-- Enable RLS on the tables
ALTER TABLE dynamic_playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE dynamic_playlist_songs ENABLE ROW LEVEL SECURITY;

-- Create policies for dynamic_playlists table
CREATE POLICY "Users can view their own playlists" 
  ON dynamic_playlists
  FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own playlists" 
  ON dynamic_playlists
  FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own playlists" 
  ON dynamic_playlists
  FOR UPDATE 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own playlists" 
  ON dynamic_playlists
  FOR DELETE 
  USING (auth.uid() = user_id);

-- Create policies for dynamic_playlist_songs table
CREATE POLICY "Users can view songs in their playlists" 
  ON dynamic_playlist_songs
  FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM dynamic_playlists 
      WHERE id = dynamic_playlist_songs.playlist_id 
      AND user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert songs into their playlists" 
  ON dynamic_playlist_songs
  FOR INSERT 
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM dynamic_playlists 
      WHERE id = dynamic_playlist_songs.playlist_id 
      AND user_id = auth.uid()
    )
  );

CREATE POLICY "Users can delete songs from their playlists" 
  ON dynamic_playlist_songs
  FOR DELETE 
  USING (
    EXISTS (
      SELECT 1 FROM dynamic_playlists 
      WHERE id = dynamic_playlist_songs.playlist_id 
      AND user_id = auth.uid()
    )
  );
