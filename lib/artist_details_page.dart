import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ArtistDetailsPage extends StatefulWidget {
  final Map<String, dynamic> artist;
  final VoidCallback? onBackPressed;
  final SupabaseClient? supabaseClient;
  final Function(Map<String, dynamic>)? onSongSelected;

  const ArtistDetailsPage({
    super.key,
    required this.artist,
    this.onBackPressed,
    this.supabaseClient,
    this.onSongSelected,
  });

  @override
  State<ArtistDetailsPage> createState() => _ArtistDetailsPageState();
}

class _ArtistDetailsPageState extends State<ArtistDetailsPage> {
  List<Map<String, dynamic>> _popularSongs = [];
  List<Map<String, dynamic>> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArtistData();
  }

  Future<void> _loadArtistData() async {
    if (widget.supabaseClient == null) return;

    setState(() => _isLoading = true);
    try {
      // Fetch popular songs
      final songsResponse = await widget.supabaseClient!
          .from('songs')
          .select()
          .eq('artist_id', widget.artist['id'])
          .order('play_count', ascending: false)
          .limit(5);

      // Fetch albums
      final albumsResponse = await widget.supabaseClient!
          .from('albums')
          .select()
          .eq('artist_id', widget.artist['id'])
          .order('release_date', ascending: false);

      setState(() {
        _popularSongs = List<Map<String, dynamic>>.from(songsResponse);
        _albums = List<Map<String, dynamic>>.from(albumsResponse);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading artist data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchArtistTopTracks() async {
    try {
      final response = await widget.supabaseClient!
          .from('songs_2')
          .select('id, title, artist, duration, audio_url, image_url, play_count')
          .eq('artist', widget.artist['name'])
          .order('play_count', ascending: false)
          .limit(5);

      if (response.isEmpty) {
        // If no top tracks found, try to get all tracks as fallback
        final fallbackResponse = await widget.supabaseClient!
            .from('songs_2')
            .select('id, title, artist, duration, audio_url, image_url, play_count')
            .eq('artist', widget.artist['name'])
            .order('created_at', ascending: false)
            .limit(5);

        if (fallbackResponse.isEmpty) {
          throw Exception('No tracks found for this artist');
        }

        return List<Map<String, dynamic>>.from(fallbackResponse);
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching artist top tracks: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchArtistAlbums() async {
    try {
      final response = await widget.supabaseClient!
          .from('albums')
          .select('id, title, artist, release_date, image_url')
          .eq('artist', widget.artist['name'])
          .order('release_date', ascending: false);

      if (response.isEmpty) {
        throw Exception('No albums found for this artist');
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching artist albums: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSimilarArtists() async {
    try {
      // First try to get artists in the same genre
      final response = await widget.supabaseClient!
          .from('artists')
          .select('id, name, image_url, followers')
          .neq('name', widget.artist['name'])
          .order('followers', ascending: false)
          .limit(6);

      if (response.isEmpty) {
        throw Exception('No similar artists found');
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching similar artists: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBackPressed,
        ),
        title: Text(
          widget.artist['name'] ?? 'Unknown Artist',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Artist header
                  Container(
                    height: 300,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: NetworkImage(widget.artist['image_url'] ?? ''),
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Artist info
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.artist['name'] ?? 'Unknown Artist',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.artist['followers'] ?? 0} followers',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Popular songs section
                        if (_popularSongs.isNotEmpty) ...[
                          const Text(
                            'Popular Songs',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _popularSongs.length,
                            itemBuilder: (context, index) {
                              final song = _popularSongs[index];
                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    song['image_url'] ?? '',
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 56,
                                      height: 56,
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.music_note),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  song['title'] ?? 'Unknown Song',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  '${song['play_count'] ?? 0} plays',
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: () {
                                    if (widget.onSongSelected != null) {
                                      widget.onSongSelected!(song);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 24),
                        // Albums section
                        if (_albums.isNotEmpty) ...[
                          const Text(
                            'Albums',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _albums.length,
                            itemBuilder: (context, index) {
                              final album = _albums[index];
                              return GestureDetector(
                                onTap: () {
                                  // TODO: Navigate to album details
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          album['image_url'] ?? '',
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: Colors.grey[800],
                                            child: const Icon(Icons.album, size: 40),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      album['title'] ?? 'Unknown Album',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      album['release_date'] ?? '',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 