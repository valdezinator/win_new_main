import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'album_view.dart';
import 'services/playlist_generator_service.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb if needed

class LibraryScreen extends StatefulWidget {
  final SupabaseClient supabaseClient;
  final Map<String, dynamic>? currentlyPlayingSong;
  const LibraryScreen({
    Key? key,
    required this.supabaseClient,
    this.currentlyPlayingSong,
  }) : super(key: key);

  @override
  _LibraryScreenState createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _isGridView = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  Future<void> _getCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser ??
        Supabase.instance.client.auth.currentSession?.user;
    if (user != null) {
      setState(() {
        _currentUserId = user.id;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPlaylists() async {
    try {
      if (_currentUserId == null) return [];
      
      final data = await widget.supabaseClient
          .from('playlist')
          .select('*, is_ai_generated') // include is_ai_generated column
          .eq('user_id', _currentUserId!)
          .order('playlist_name');

      return List<Map<String, dynamic>>.from(data);      
    } catch (e) {
      print('Unexpected error fetching playlists: $e');
      return [];
    }
  }

  void _showCreatePlaylistDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E2329),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Create Playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                _buildCreateOption(
                  context,
                  'Your Playlist',
                  Icons.playlist_add,
                  () => _createCustomPlaylist(),
                ),
                const SizedBox(height: 16),
                _buildCreateOption(
                  context,
                  'AI Playlist',
                  Icons.auto_awesome,
                  () => _createAIPlaylist(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateOption(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }

  void _createCustomPlaylist() async {
    final TextEditingController nameController = TextEditingController();
    
    final String? playlistName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E2329),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'New Playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Playlist name',
                    hintStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, nameController.text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (playlistName != null && playlistName.isNotEmpty) {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session?.user == null) {
        print('Error: No active session found');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login to create a playlist')),
        );
        return;
      }
      try {
        await client.from('playlist').insert({
          'playlist_name': playlistName,
          'user_id': session!.user.id,
          'image_url': 'https://path.to/default/playlist/image.jpg',
        });
        setState(() {}); // Refresh the list
      } catch (e) {
        print('Error creating playlist: $e');
      }
    }
  }

  // Add helper function to parse duration from "mm:ss" to seconds.
  int _parseDuration(String durationStr) {
    final parts = durationStr.split(':');
    if (parts.length != 2) return 0;
    final minutes = int.tryParse(parts[0]) ?? 0;
    final seconds = int.tryParse(parts[1]) ?? 0;
    return minutes * 60 + seconds;
  }

  void _createAIPlaylist() async {
    final TextEditingController promptController = TextEditingController();
    final playlistGenerator = PlaylistGeneratorService(supabaseClient: widget.supabaseClient);
    
    final String? prompt = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E2329),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Create AI Playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Describe the kind of playlist you want:',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: promptController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g., "A chill playlist with some upbeat pop and songs like The Weeknd"',
                    hintStyle: TextStyle(color: Colors.grey.withOpacity(0.7)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, promptController.text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Generate'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (prompt != null && prompt.isNotEmpty) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Dialog(
            backgroundColor: Color(0xFF1E2329),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Generating your playlist...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      );

      try {
        // Generate playlist
        final songs = await playlistGenerator.generatePlaylist(prompt);
        
        // Pop the loading dialog before any potential early returns
        Navigator.of(context).pop();
        
        if (songs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not generate playlist. Please try a different prompt.')),
          );
          return;
        }

        // Generate description
        final analysis = playlistGenerator.analyzePrompt(prompt);
        final description = playlistGenerator.generatePlaylistDescription(analysis);
        
        // Create playlist entry in the public.playlist table
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please login to create a playlist')),
          );
          return;
        }

        final playlistData = await widget.supabaseClient
            .from('playlist')
            .insert({
              'playlist_name': 'AI: ${description.length > 30 ? description.substring(0, 27) + '...' : description}',
              'user_id': user.id,
              'description': description,
              'image_url': 'https://path.to/default/ai/playlist/image.jpg',
              'is_ai_generated': true,
            })
            .select()
            .single();

        // Insert generated songs into the public.ai_playlists table
        await widget.supabaseClient.from('ai_playlists').insert(
          songs.map((song) {
            // Convert duration to int if needed.
            final rawDuration = song['duration'];
            int duration;
            if (rawDuration is String && rawDuration.contains(':')) {
              duration = _parseDuration(rawDuration);
            } else if (rawDuration is int) {
              duration = rawDuration;
            } else {
              duration = 0;
            }
            return {
              'playlist_id': playlistData['id'],
              'title': song['title'] ?? '',
              'artist': song['artist'] ?? '',
              'genre': song['genre'] ?? '',
              'duration': duration, // conversion logic added
              'audio_url': song['audio_url'] ?? '',
              'image_url': song['image_url'] ?? '',
              'user_id': user.id,
            };
          }).toList(),
        );

        setState(() {}); // Refresh the list

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Your AI playlist has been created!'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AlbumView(
                      album: playlistData,
                      supabaseClient: widget.supabaseClient,
                      onSongSelected: (song) {
                        print("Song selected: $song");
                      },
                      currentlyPlayingSong: widget.currentlyPlayingSong,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } catch (e) {
        // Make sure to dismiss loading dialog on error
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating playlist: $e')),
        );
      }
    }
  }

  Widget _buildGridView(List<Map<String, dynamic>> playlists) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _buildPlaylistCard(playlist);
      },
    );
  }

  Widget _buildListView(List<Map<String, dynamic>> playlists) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _buildPlaylistListItem(playlist);
      },
    );
  }

  Widget _buildPlaylistCard(Map<String, dynamic> playlist) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumView(
              album: playlist,
              supabaseClient: widget.supabaseClient,
              onSongSelected: (song) {
                // ...handle song selection...
                print("Song selected: $song");
              },
              currentlyPlayingSong: widget.currentlyPlayingSong,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  image: DecorationImage(
                    image: NetworkImage(playlist['image_url'] ?? ''),
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                playlist['playlist_name'] ?? 'Unnamed Playlist',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistListItem(Map<String, dynamic> playlist) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumView(
              album: playlist,
              supabaseClient: widget.supabaseClient,
              onSongSelected: (song) {
                // ...handle song selection...
                print("Song selected: $song");
              },
              currentlyPlayingSong: widget.currentlyPlayingSong,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              image: DecorationImage(
                image: NetworkImage(playlist['image_url'] ?? ''),
                fit: BoxFit.cover,
                onError: (_, __) {},
              ),
            ),
          ),
          title: Text(
            playlist['playlist_name'] ?? 'Unnamed Playlist',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: const Icon(Icons.more_vert, color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with view toggle and create button
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Playlists',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isGridView ? Icons.view_list : Icons.grid_view,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isGridView = !_isGridView;
                      });
                    },
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _showCreatePlaylistDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Playlist'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Playlists content
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchPlaylists(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Error loading playlists',
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }

              final playlists = snapshot.data ?? [];
              
              if (playlists.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.playlist_add,
                        color: Colors.grey,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No playlists yet',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _showCreatePlaylistDialog,
                        child: Text('Create Your First Playlist'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return _isGridView
                  ? _buildGridView(playlists)
                  : _buildListView(playlists);
            },
          ),
        ),
      ],
    );
  }
}