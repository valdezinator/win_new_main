import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'album_view.dart';
import 'services/playlist_generator_service.dart';
import 'services/favorites_service.dart'; // Import FavoritesService
import 'dart:io'; // Import for File
import 'package:file_picker/file_picker.dart'; // Import file_picker
import 'dart:ui'; // Import for BackdropFilter
import 'package:shimmer/shimmer.dart';

class LibraryScreen extends StatefulWidget {
  final SupabaseClient supabaseClient;
  final Map<String, dynamic>? currentlyPlayingSong;
  final Function(Map<String, dynamic>)? onAlbumSelected;

  const LibraryScreen({
    super.key,
    required this.supabaseClient,
    this.currentlyPlayingSong,
    this.onAlbumSelected,
  });

  @override
    State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  bool _isGridView = true;
  String? _currentUserId;
  File? _playlistCoverImage; // Variable to hold the selected image
  Map<String, dynamic>? _selectedPlaylist; // Variable to hold the selected playlist for deletion
  bool _isMenuVisible = false; // Track visibility of the context menu
  final FavoritesService _favoritesService = FavoritesService(); // Add FavoritesService instance
  List<Map<String, dynamic>> _favoritedAlbums = []; // Add favorited albums list
  bool _isLoadingFavorites = false; // Add loading state for favorites
  int _currentTabIndex = 0; // Add tab index for switching between playlists and favorites

  // Add animation controller for view transitions
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();

    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentUser() async {
    // First check for current session
    final session = Supabase.instance.client.auth.currentSession;
    final user = session?.user;

    if (user != null) {
      setState(() {
        _currentUserId = user.id;
      });
      // Load favorited albums after getting user
      _loadFavoritedAlbums();
    } else {
      // If no session, show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to view your playlists'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadFavoritedAlbums() async {
    setState(() {
      _isLoadingFavorites = true;
    });

    try {
      final favoritedAlbums = await _favoritesService.getFavoritedAlbums();
      if (mounted) {
        setState(() {
          _favoritedAlbums = favoritedAlbums;
          _isLoadingFavorites = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFavorites = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading favorite albums: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTabButton(String text, int index) {
    final isSelected = _currentTabIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _currentTabIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchPlaylists() async {
    try {
      if (_currentUserId == null) {
        return [];
      }

      final data = await widget.supabaseClient
          .from('playlist')  // Changed back to 'playlist' as shown in policies
          .select('id, playlist_name, image_url, user_id, description, created_at')
          .eq('user_id', _currentUserId!)
          .order('created_at', ascending: false);

      if (data != null) {
        final playlists = List<Map<String, dynamic>>.from(data);
        return playlists;
      }

      return [];
    } catch (e, stackTrace) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading playlists: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return [];
    }
  }

  Future<void> _showCreatePlaylistDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E2329),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 500,
            height: 500,
          child: Padding(
              padding: const EdgeInsets.all(24.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // Header
                const Text(
                  'Create Playlist',
                  style: TextStyle(
                    color: Colors.white,
                      fontSize: 24,
                    fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Main content row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image selection container
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 150,  // Larger image container
                          height: 150, // Square aspect ratio
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                            image: _playlistCoverImage != null
                                ? DecorationImage(
                                    image: FileImage(_playlistCoverImage!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _playlistCoverImage == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate,
                                      color: Colors.white70,
                                      size: 40,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Choose photo',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Text fields column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                            TextField(
                              controller: nameController,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
                  decoration: const InputDecoration(
                                hintText: 'Add a name',
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
                            TextField(
                              controller: descriptionController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Add an optional description',
                                hintStyle: TextStyle(color: Colors.grey),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Bottom buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () {
                          Navigator.pop(context);
                          _createPlaylist(
                            nameController.text,
                            descriptionController.text,
                          );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Create',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ),
                  ],
                ),
              ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result != null) {
      final selectedFilePath = result.files.single.path!;

      // Check if the file exists
      final file = File(selectedFilePath);
      if (await file.exists()) {
        setState(() {
          _playlistCoverImage = file;
        });
      }
    }
  }

  Future<void> _createPlaylist(String playlistName, String description) async {
    if (playlistName.isNotEmpty && _currentUserId != null) {
      final client = Supabase.instance.client;
      try {
        String imageUrl = '';
        if (_playlistCoverImage != null) {
          imageUrl = await _uploadImage(_playlistCoverImage!);
        }

        await client.from('playlists').insert({  // Changed from 'playlist' to 'playlists'
          'playlist_name': playlistName,
          'description': description,
          'user_id': _currentUserId!,
          'image_url': imageUrl,
          'created_at': DateTime.now().toIso8601String(),
        });
        setState(() {}); // Refresh the list
      } catch (e) {
        //print('Error creating playlist: $e');
      }
    }
  }

  Future<String> _uploadImage(File image) async {
    // Upload the image to Supabase Storage and return the public URL
    final fileName = image.path.split('/').last; // Get the file name
    final response = await Supabase.instance.client.storage
        .from('playlist_covers') // Replace with your bucket name
        .upload(fileName, image);

    // Get the public URL
    final publicUrl = Supabase.instance.client.storage
        .from('playlist_covers') // Replace with your bucket name
        .getPublicUrl(fileName);

    return publicUrl; // Return the public URL
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
                        //print("Song selected: $song");
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

  void _showContextMenu(BuildContext context, Map<String, dynamic> playlist, Offset position) {
    setState(() {
      _selectedPlaylist = playlist;
    });

    // Show the context menu at the cursor position
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
      items: [
        const PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete Playlist'),
        ),
        const PopupMenuItem<String>(
          value: 'cancel',
          child: Text('Cancel'),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _deletePlaylist();
      }
    });
  }

  void _deletePlaylist() async {
    if (_selectedPlaylist != null) {
      final response = await widget.supabaseClient
          .from('playlists')  // Changed from 'playlist' to 'playlists'
          .delete()
          .eq('id', _selectedPlaylist!['id']);

      if (response != null && response.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playlist deleted successfully!')),
        );
        setState(() {
          _isMenuVisible = false;
        });
      } else {
        String errorMessage = response?.error?.message ?? 'Unknown error occurred.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting playlist: $errorMessage')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playlist selected for deletion.')),
      );
    }
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[850]!,
      highlightColor: Colors.grey[700]!,
      child: _isGridView
          ? GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _calculateCrossAxisCount(),
                childAspectRatio: 0.85,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
              ),
              itemCount: 6,
              itemBuilder: (context, index) => Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 6,
              itemBuilder: (context, index) => Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
    );
  }

  int _calculateCrossAxisCount() {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1500) return 6;
    if (screenWidth > 1200) return 5;
    if (screenWidth > 900) return 4;
    if (screenWidth > 600) return 3;
    return 2;
  }

  Widget _buildGridView(List<Map<String, dynamic>> playlists) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _calculateCrossAxisCount(),
        childAspectRatio: 0.85,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
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
    final bool isCurrentlyPlaying = widget.currentlyPlayingSong != null &&
        widget.currentlyPlayingSong!['album_id'] == playlist['id'];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          _showContextMenu(context, playlist, details.globalPosition);
        },
        child: StatefulBuilder(
          builder: (context, setState) {
            bool isHovered = false;

            return MouseRegion(
              onEnter: (_) => setState(() => isHovered = true),
              onExit: (_) => setState(() => isHovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isHovered
                      ? Colors.white.withOpacity(0.1)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (widget.onAlbumSelected != null) {
                        widget.onAlbumSelected!(playlist);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AlbumView(
                              album: playlist,
                              supabaseClient: widget.supabaseClient,
                              onSongSelected: (song) {},
                              currentlyPlayingSong: widget.currentlyPlayingSong,
                            ),
                          ),
                        );
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Cover image with fade transition
                              Hero(
                                tag: 'playlist_${playlist['id']}',
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                  child: Image.network(
                                    playlist['image_url'] ?? '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.grey[800],
                                      child: const Icon(
                                        Icons.music_note,
                                        color: Colors.white54,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Play overlay with animation
                              if (isHovered)
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: isHovered ? 1.0 : 0.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                    ),
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.black,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // Currently playing indicator with animation
                              if (isCurrentlyPlaying)
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 200),
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.volume_up,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Playing',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                playlist['playlist_name'] ?? 'Unnamed Playlist',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                playlist['description'] ?? 'Your playlist',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        ),
      ),
    );
  }

  Widget _buildPlaylistListItem(Map<String, dynamic> playlist) {
    final bool isCurrentlyPlaying = widget.currentlyPlayingSong != null &&
        widget.currentlyPlayingSong!['album_id'] == playlist['id'];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          _showContextMenu(context, playlist, details.globalPosition);
        },
        child: StatefulBuilder(
          builder: (context, setStateLocal) {
            bool isHovered = false;

            return MouseRegion(
              onEnter: (_) => setStateLocal(() => isHovered = true),
              onExit: (_) => setStateLocal(() => isHovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                decoration: BoxDecoration(
                  color: isHovered
                      ? Colors.white.withOpacity(0.1)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (widget.onAlbumSelected != null) {
                        widget.onAlbumSelected!(playlist);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AlbumView(
                              album: playlist,
                              supabaseClient: widget.supabaseClient,
                              onSongSelected: (song) {},
                              currentlyPlayingSong: widget.currentlyPlayingSong,
                            ),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Row(
                        children: [
                          // Cover image with play overlay on hover
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Image.network(
                                    playlist['image_url'] ?? '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.grey[800],
                                      child: const Icon(
                                        Icons.music_note,
                                        color: Colors.white54,
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Play overlay on hover
                              if (isHovered)
                                Positioned.fill(
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.black,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(width: 16),

                          // Playlist info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playlist['playlist_name'] ?? 'Unnamed Playlist',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  playlist['description'] ?? 'Your playlist',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          // Currently playing indicator
                          if (isCurrentlyPlaying)
                            Container(
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.volume_up,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Playing',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // More options icon
                          Icon(
                            Icons.more_vert,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        ),
      ),
    );
  }

  Widget _buildPlaylistsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchPlaylists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerLoading();
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
                  child: const Text('Create Your First Playlist'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isGridView
              ? _buildGridView(playlists)
              : _buildListView(playlists),
        );
      },
    );
  }

  Widget _buildFavoritesContent() {
    if (_isLoadingFavorites) {
      return _buildShimmerLoading();
    }

    if (_favoritedAlbums.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.favorite_border,
              color: Colors.grey,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No favorite albums yet',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start exploring and add albums to your favorites',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _isGridView
          ? _buildGridView(_favoritedAlbums)
          : _buildListView(_favoritedAlbums),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // Header with view toggle and create button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.05),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Title and action buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Title with icon
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.library_music,
                              color: Colors.purple,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            'Your Library',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),

                      // Action buttons
                      Row(
                        children: [
                          // View toggle button
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() {
                                    _isGridView = !_isGridView;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isGridView ? Icons.view_list : Icons.grid_view,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isGridView ? 'List View' : 'Grid View',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // AI Playlist button (only show for playlists tab)
                          if (_currentTabIndex == 0) ...[
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: _createAIPlaylist,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome,
                                          color: Colors.deepPurple,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'AI Playlist',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 16),
                          ],

                          // Create playlist button (only show for playlists tab)
                          if (_currentTabIndex == 0)
                            ElevatedButton.icon(
                              onPressed: _showCreatePlaylistDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Create Playlist'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  // Tab bar
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTabButton('Your Playlists', 0),
                        _buildTabButton('Favorite Albums', 1),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Playlists content with animations
            Expanded(
              child: _currentTabIndex == 0
                  ? _buildPlaylistsContent()
                  : _buildFavoritesContent(),
            ),
          ],
        ),

        // Context menu for deleting playlist
        if (_isMenuVisible)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isMenuVisible = false;
                });
              },
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Options',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _deletePlaylist,
                          child: const Text('Delete Playlist'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}