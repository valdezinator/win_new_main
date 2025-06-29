import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:supabase/supabase.dart';
import 'dart:async';
import 'dart:ui'; // Add this import for ImageFilter
import 'dart:io'; // Add this import for InternetAddress
import 'widgets/queue_list.dart';
import 'services/download_service.dart';
import 'package:cached_network_image/cached_network_image.dart'; // NEW import for caching images
import 'package:shimmer/shimmer.dart'; // Add shimmer package
import 'services/backblaze_service.dart'; // Import BackblazeService
import 'services/favorites_service.dart'; // Import FavoritesService

class AlbumView extends StatefulWidget {
  final Map<String, dynamic> album;
  final SupabaseClient supabaseClient;
  final Function(Map<String, dynamic>) onSongSelected;
  final Map<String, dynamic>? currentlyPlayingSong;
  final bool inMainLayout; // Flag to indicate if it's in the main layout
  final VoidCallback? onBackPressed; // Callback for back navigation

  const AlbumView({
    super.key,
    required this.album,
    required this.supabaseClient,
    required this.onSongSelected,
    this.currentlyPlayingSong,
    this.inMainLayout = false, // Default to false for backward compatibility
    this.onBackPressed,
  });

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> with SingleTickerProviderStateMixin {
  PaletteGenerator? _palette;
  List<Map<String, dynamic>> songs = [];
  bool isLoading = true;
  int? currentPlayingIndex;
  bool showQueue = false;
  int? hoveredIndex;
  bool isPlayButtonHovered = false;
  final DownloadService _downloadService = DownloadService();
  bool _isDownloading = false;
  Map<String, double> _downloadProgress = {};
  double _totalDownloadProgress = 0.0;
  bool _isDownloaded = false;
  Map<String, dynamic>? _currentSong; // NEW state variable
  bool _isFavorited = false; // Add favorites state
  bool _isFavoritesLoading = false; // Add loading state for favorites

  Timer? _downloadProgressTimer;

  // Add animation controller for transitions
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final BackblazeService _backblazeService = BackblazeService(); // Add BackblazeService instance
  final FavoritesService _favoritesService = FavoritesService(); // Add FavoritesService instance

  @override
  void initState() {
    super.initState();
    _currentSong = widget.currentlyPlayingSong;
    _loadPalette();

    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);

    // Debug: Check authentication state
    final user = widget.supabaseClient.auth.currentUser;
    print('AlbumView - Current user: ${user?.id}');
    print('AlbumView - Is authenticated: ${user != null}');
    print('AlbumView - Album data: ${widget.album}');

    // Delay loading songs to ensure initState is complete
    Future.microtask(() {
      if (mounted) {
        _loadSongs().then((_) {
          if (_currentSong != null && mounted) {
            setState(() {
              // Update currentPlayingIndex if needed
              // Assuming that _currentSong exists in songs:
              // (Keep existing logic if desired)
            });
          }
          _checkDownloadState();
          _checkFavoriteState(); // Add favorites checking
        });
      }
    });

    // Listen for real-time download progress updates
    _downloadService.downloadProgress.listen((progress) {
      if (mounted) {
        setState(() {
          _downloadProgress = progress;
          if (progress.containsKey('Total')) {
            _totalDownloadProgress = progress['Total'] ?? 0.0;
          }
        });
      }
    });

    // Set up a timer to refresh the download button every 10 seconds
    _downloadProgressTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _isDownloading) {
        setState(() {
          // This will trigger a UI refresh of the download button
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    // Cancel the download progress timer
    _downloadProgressTimer?.cancel();

    // Only clear currentPlayingIndex, don't stop the song
    currentPlayingIndex = null;
    super.dispose();
  }

  Future<void> _checkDownloadState() async {
    final isDownloaded = await _downloadService.isAlbumDownloaded(widget.album['id'].toString());
    if (mounted) {
      setState(() {
        _isDownloaded = isDownloaded;
      });
    }
  }

  Future<void> _checkFavoriteState() async {
    final isFavorited = await _favoritesService.isAlbumFavorited(widget.album['id'].toString());
    if (mounted) {
      setState(() {
        _isFavorited = isFavorited;
      });
    }
  }

  Future<void> _addToFavorites() async {
    if (_isFavoritesLoading) return;

    setState(() {
      _isFavoritesLoading = true;
    });

    try {
      final newFavoriteState = await _favoritesService.toggleAlbumFavorite(widget.album['id'].toString());
      
      if (mounted) {
        setState(() {
          _isFavorited = newFavoriteState;
          _isFavoritesLoading = false;
        });

        // Show feedback to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  newFavoriteState ? Icons.favorite : Icons.favorite_border,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  newFavoriteState 
                    ? 'Added to Favorites' 
                    : 'Removed from Favorites',
                ),
              ],
            ),
            backgroundColor: newFavoriteState ? Colors.green : Colors.grey[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFavoritesLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating favorites: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void _loadPalette() async {
    if (widget.album['image_url'] != null) {
      try {
        // Resolve image URL using BackblazeService
        final resolvedImageUrl = await _backblazeService.getImageUrl(
          widget.album['image_url'],
          widget.album['image_identifier'],
        );
        final imageProvider = NetworkImage(resolvedImageUrl);
        final paletteGenerator = await PaletteGenerator.fromImageProvider(imageProvider);
        setState(() {
          _palette = paletteGenerator;
        });
      } catch (e) {
        print('Error loading palette: $e');
      }
    }
  }  // Helper method to show error messages after widget is fully initialized
  void _showErrorMessage(String message, {bool isError = true}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.black87,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadSongs() async {
    setState(() => isLoading = true);
    try {
      final isPlaylist = widget.album['playlist_name'] != null;
      final isDynamicPlaylist = widget.album['playlist_type'] != null;
      final albumId = widget.album['id'].toString();

      // First check if the album is downloaded
      final isDownloaded = await _downloadService.isAlbumDownloaded(albumId);

      // Check if we're online
      bool isOnline = false;
      try {
        final result = await InternetAddress.lookup('google.com');
        isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (e) {
        // We're offline
        isOnline = false;
      }

      // If album is downloaded and we're offline, load from local storage
      if (isDownloaded && !isOnline) {
        final albumMetadata = await _downloadService.getAlbumMetadata(albumId);

        if (albumMetadata != null && albumMetadata['songs'] != null) {
          final downloadedSongs = List<Map<String, dynamic>>.from(albumMetadata['songs']);

          if (mounted) {
            setState(() {
              songs = downloadedSongs;
              isLoading = false;
              _isDownloaded = true;

              if (widget.currentlyPlayingSong != null) {
                currentPlayingIndex = songs.indexWhere(
                  (song) => song['id'] == widget.currentlyPlayingSong!['id']
                );
              }
            });
          }
          return;
        }
      }

      // If we're offline and the album is not downloaded, show a message
      if (!isOnline && !isDownloaded) {
        if (mounted) {
          setState(() {
            isLoading = false;
            songs = [];
          });

          Future.microtask(() {
            _showErrorMessage(
              'You\'re offline and this album is not downloaded',
              isError: true
            );
          });
        }
        return;
      }

      // If we're online, proceed with normal loading from Supabase
      // Check authentication first
      final userId = widget.supabaseClient.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          isLoading = false;
          songs = [];
        });
        // Don't show error message here - will be handled after initState completes
        throw Exception('User not logged in');
      }

      final response = isDynamicPlaylist
          ? await widget.supabaseClient
              .from('dynamic_playlist_songs')
              .select('''
                songs_2!inner (
                  id,
                  title,
                  artist,
                  audio_url,
                  image_url,
                  file_identifier,
                  duration
                ),
                dynamic_playlists!inner (
                  id,
                  user_id,
                  playlist_type
                )
              ''')
              .eq('dynamic_playlists.id', widget.album['id'])
              .eq('dynamic_playlists.user_id', userId)
          : isPlaylist
              ? await widget.supabaseClient
                  .from('playlist_songs')
                  .select('''
                    *,
                    songs_2!inner (
                      id,
                      title,
                      artist,
                      audio_url,
                      image_url,
                      file_identifier,
                      duration
                    )
                  ''')
                  .eq('playlist_id', widget.album['id'])
                  .order('added_at', ascending: false)
              : await widget.supabaseClient
                  .from('songs_2')
                  .select('id, title, artist, audio_url, image_url, file_identifier, duration')
                  .eq('album_id', widget.album['id']);

      // Handle empty response
      if ((response as List).isEmpty) {
        setState(() {
          songs = [];
          isLoading = false;
        });

        // Schedule error message to be shown after initState completes
        Future.microtask(() {
          _showErrorMessage(
            'No songs found in this ${isDynamicPlaylist ? 'playlist' : 'album'}',
            isError: false
          );
        });
        return;
      }

      // Process and validate the songs
      final validSongs = (response as List)
          .map((song) {
            Map<String, dynamic>? songData;
            if (isDynamicPlaylist) {
                songData = song['songs_2'];
            } else if (isPlaylist) {
                songData = song['songs_2'];
            } else {
                songData = song;
            }

            // Don't filter out songs with null audio_url - show them but mark as not playable
            if (songData == null) {
              return null;
            }

            // Clean and validate the image URL
            String? imageUrl = songData['image_url'] ?? widget.album['image_url'];
            if (imageUrl != null) {
              // Remove any trailing '?' from the image URL
              imageUrl = imageUrl.endsWith('?') ? imageUrl.substring(0, imageUrl.length - 1) : imageUrl;
              // Ensure URL is valid
              try {
                final uri = Uri.parse(imageUrl);
                if (!uri.hasScheme || !uri.hasAuthority) {
                  imageUrl = null;
                }
              } catch (e) {
                // Log invalid image URL
                imageUrl = null;
              }
            }

            return {
              'id': songData['id'],
              'title': songData['title'] ?? 'Unknown Title',
              'artist': songData['artist'] ?? widget.album['artist'] ?? 'Unknown Artist',
              'audio_url': songData['audio_url'], // Can be null
              'image_url': imageUrl,
              'duration': songData['duration'],
              'position': song['position'], // For dynamic playlists
              'file_identifier': songData['file_identifier'],
              'image_identifier': songData['image_identifier'] != null
                  ? (songData['image_identifier'].startsWith('images/')
                      ? songData['image_identifier']
                      : 'images/${songData['image_identifier']}')
                  : null,
              'is_playable': songData['audio_url'] != null, // Add flag to indicate if song is playable
            };
          })
          .where((song) => song != null)
          .cast<Map<String, dynamic>>()
          .toList();

      if (mounted) {
        setState(() {
          songs = validSongs;
          isLoading = false;

          if (widget.currentlyPlayingSong != null) {
            currentPlayingIndex = songs.indexWhere(
              (song) => song['id'] == widget.currentlyPlayingSong!['id']
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          songs = [];
        });

        // Schedule error message to be shown after initState completes
        Future.microtask(() {
          _showErrorMessage('Error loading songs: $e');
        });
      }
    }
  }

  void _playAll() {
    if (songs.isNotEmpty) {
      // Find the first playable song
      final playableSong = songs.firstWhere(
        (song) => song['is_playable'] ?? true,
        orElse: () => songs.first, // Fallback to first song if none are playable
      );
      
      currentPlayingIndex = songs.indexOf(playableSong);
      _playSong(playableSong);
    }
  }

  void _playSong(Map<String, dynamic> song) async {
    // Check if song is playable
    if (song['audio_url'] == null && !_isDownloaded) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.block, color: Colors.white),
                const SizedBox(width: 8),
                Text('Cannot play: ${song['title']} - Audio not available'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
      return;
    }

    try {
      // Resolve audio URL using BackblazeService if needed
      final audioUrl = await _backblazeService.getAudioUrl(
        song['audio_url'],
        song['file_identifier'],
      );
      print('Resolved audio URL (AlbumView): $audioUrl'); // Debug log

      // Format queue data first to ensure all songs have required fields
      final formattedQueue = songs.map((s) {
        final songData = s['songs_2'] ?? s;
        var duration = songData['duration'];
        if (duration is String && duration.contains(':')) {
          final parts = duration.split(':');
          duration = (int.parse(parts[0]) * 60) + int.parse(parts[1]);
        }
        return {
          ...Map<String, dynamic>.from(songData),
          'id': songData['id'],
          'title': songData['title'] ?? 'Unknown',
          'artist': songData['artist'] ?? widget.album['artist'] ?? 'Unknown Artist',
          'audio_url': songData['audio_url'],
          'image_url': songData['image_url'] ?? widget.album['image_url'],
          'album': widget.album['playlist_name'] ?? widget.album['title'],
          'album_id': widget.album['id'],
          'duration': duration,
          'downloaded': _isDownloaded,
          'filename': _isDownloaded ? 'song_${songData['id']}' : null,
        };
      }).toList();

      var songDuration = song['duration'];
      if (songDuration is String && songDuration.contains(':')) {
        final parts = songDuration.split(':');
        songDuration = (int.parse(parts[0]) * 60) + int.parse(parts[1]);
      }

      final songWithAlbumContext = {
        ...Map<String, dynamic>.from(song),
        'id': song['id'],
        'album': widget.album['playlist_name'] ?? widget.album['title'],
        'album_id': widget.album['id'],
        'album_art': widget.album['image_url'],
        'image_url': song['image_url'] ?? widget.album['image_url'],
        'artist': song['artist'] ?? widget.album['artist'] ?? 'Unknown Artist',
        'title': song['title'] ?? 'Unknown Title',
        'duration': songDuration,
        'song_lyrics': song['song_lyrics'],
        'queue': formattedQueue,
        'downloaded': _isDownloaded,
        'filename': _isDownloaded ? 'song_${song['id']}' : null,
        'audio_url': audioUrl, // Use resolved audio URL
      };

      _currentSong = songWithAlbumContext;
      currentPlayingIndex = songs.indexWhere((s) => s['id'] == song['id']);

      widget.onSongSelected(songWithAlbumContext);
    } catch (e) {
      print('Error resolving audio URL (AlbumView): $e'); // Debug log
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing song: ${e.toString()}')),
        );
      }
    }
  }

  String _formatDuration(dynamic duration) {
    if (duration == null) return '0:00';

    if (duration is String) {
      // If it's already in MM:SS format, return as is
      if (duration.toString().contains(':')) {
        return duration;
      }

      // Try to parse as seconds if it's a numeric string
      try {
        final seconds = int.parse(duration);
        final minutes = seconds ~/ 60;
        final remainingSeconds = seconds % 60;
        return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
      } catch (e) {
        return '0:00';
      }
    } else if (duration is int) {
      final minutes = duration ~/ 60;
      final remainingSeconds = duration % 60;
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }

    return '0:00';
  }

  Widget _buildColumnHeaders() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          // Track number column
          SizedBox(
            width: 30,
            child: Text(
              "#",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 20),
          // Song Image space
          SizedBox(width: 40),
          SizedBox(width: 16),
          // Title column
          Expanded(
            child: Text(
              "TITLE",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Duration column
          SizedBox(
            width: 80,
            child: Text(
              "DURATION",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 40), // Space for more options
        ],
      ),
    );
  }

  Widget _buildAlbumHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        
        return Container(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 16 : 32,
            isCompact ? 16 : 32,
            isCompact ? 16 : 32,
            isCompact ? 16 : 32,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildAlbumCover(isCompact),
              SizedBox(width: isCompact ? 16 : 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      widget.album['playlist_name'] ?? widget.album['title'] ?? 'Unknown Album',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28, // Reduced from 36
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.album['artist'] ?? 'Various Artists',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _playAll,
                          icon: const Icon(Icons.play_arrow, color: Colors.black),
                          label: const Text('Play All', style: TextStyle(color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        _buildDownloadButton(),
                        const SizedBox(width: 16),
                        _buildFavoriteButton(),
                        const SizedBox(width: 16),
                        _buildAlbumMoreOptionsMenu(),
                        // const Spacer(), // Pushes queue button to the right
                        // IconButton(
                        //   icon: const Icon(Icons.queue_music, color: Colors.white),
                        //   tooltip: 'Show Queue',
                        //   onPressed: () {
                        //     setState(() {
                        //       showQueue = !showQueue;
                        //     });
                        //   },
                        // ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumCover([bool isCompact = false]) {
    final size = isCompact ? 120.0 : 200.0;
    
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: widget.album['image_url'] != null
                ? FutureBuilder<String>(
                    future: _backblazeService.getImageUrl(
                      widget.album['image_url'],
                      widget.album['image_identifier'],
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          color: Colors.grey[900],
                          child: const Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return Container(
                          color: Colors.grey[800],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, color: Colors.white54, size: 48),
                              SizedBox(height: 8),
                              Text(
                                'Error loading image',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return CachedNetworkImage(
                        imageUrl: snapshot.data!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[900],
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[800],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.album, color: Colors.white, size: 50),
                              SizedBox(height: 8),
                              Text(
                                'Image not available',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    color: Colors.grey[800],
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.album, color: Colors.white, size: 50),
                        SizedBox(height: 8),
                        Text(
                          'No cover image',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        // Show download badge if album is downloaded
        if (_isDownloaded)
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green, width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.download_done,
                    color: Colors.green,
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Downloaded',
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
    );
  }

  Widget _buildAlbumMoreOptionsMenu() {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMenuItem(
                        icon: _isFavorited ? Icons.favorite : Icons.favorite_border,
                        text: _isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
                        onTap: () {
                          Navigator.pop(context);
                          _addToFavorites();
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.person_outline,
                        text: 'Follow Artist',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Follow artist
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.library_add,
                        text: 'Add to Playlist',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Show playlist selection
                        },
                      ),
                      _buildMenuItem(
                        icon: _isDownloaded ? Icons.download_done : Icons.download_outlined,
                        text: _isDownloaded ? 'Downloaded' : 'Download Album',
                        onTap: () {
                          Navigator.pop(context);
                          if (!_isDownloaded) _downloadAlbum();
                        },
                      ),
                      _buildDivider(),
                      _buildMenuItem(
                        icon: Icons.share,
                        text: 'Share Album',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Share album
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.info_outline,
                        text: 'Album Info',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Show album info
                        },
                      ),
                      if (widget.album['artist_id'] != null) ...[
                        _buildDivider(),
                        _buildMenuItem(
                          icon: Icons.person,
                          text: 'Go to Artist Page',
                          onTap: () {
                            Navigator.pop(context);
                            // TODO: Navigate to artist page
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.1),
          ),
          child: const Icon(
            Icons.more_horiz,
            color: Colors.white70,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: 1,
      color: Colors.white.withOpacity(0.1),
    );
  }

  Widget _buildMoreOptionsMenu(Map<String, dynamic> song) {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false, // Disable the container item
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 220,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMenuItem(
                        icon: Icons.playlist_remove,
                        text: 'Remove from Playlist',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Implement remove functionality
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.playlist_add,
                        text: 'Add to Another Playlist',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Show playlist selection dialog
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.person,
                        text: 'Go to Artist Page',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Navigate to artist page
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.album,
                        text: 'Go to Album Page',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Navigate to album page
                        },
                      ),
                      _buildMenuItem(
                        icon: Icons.share,
                        text: 'Share',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Show share dialog
                        },
                      ),                      if (song['downloadable'] == true)
                        _buildMenuItem(
                          icon: Icons.download,
                          text: 'Download',
                          onTap: () {
                            Navigator.pop(context);
                            _downloadSong(song);
                          },
                        ),
                      _buildMenuItem(
                        icon: Icons.favorite_border,
                        text: 'Add to Favorites',
                        onTap: () {
                          Navigator.pop(context);
                          _addToFavorites();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.1),
            ),
            child: const Icon(
              Icons.more_vert,
              color: Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSongRow(MapEntry<int, Map<String, dynamic>> entry) {
    final isCurrentSong = currentPlayingIndex != null && currentPlayingIndex == entry.key;
    final isHovered = hoveredIndex == entry.key;
    final isPlayable = entry.value['is_playable'] ?? true; // Default to true for backward compatibility

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 56,
      decoration: BoxDecoration(
        color: isCurrentSong
            ? Colors.green.withOpacity(0.15)
            : isHovered
                ? Colors.white.withOpacity(0.1)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isPlayable ? () => _playSong(entry.value) : null, // Disable tap for non-playable songs
          onHover: (hover) {
            setState(() {
              hoveredIndex = hover ? entry.key : null;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              // Track Number
              SizedBox(
                width: 30,
                child: Text(
                  '${entry.key + 1}',
                  style: TextStyle(
                    color: isCurrentSong ? Colors.green : (isPlayable ? Colors.white70 : Colors.grey[600]),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 20),
              // Song Image
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: FutureBuilder<String>(
                      future: _backblazeService.getImageUrl(
                        entry.value['image_url'],
                        entry.value['image_identifier'],
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey[850],
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }

                        if (snapshot.hasError) {
                          return Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey[850],
                            child: const Icon(Icons.error_outline, color: Colors.white54, size: 20),
                          );
                        }

                        return CachedNetworkImage(
                          imageUrl: snapshot.data!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey[850],
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey[850],
                            child: const Icon(Icons.music_note, color: Colors.white54, size: 20),
                          ),
                        );
                      },
                    ),
                  ),
                  // Show download indicator in the corner if downloaded
                  if (_isDownloaded)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.download_done,
                          color: Colors.green,
                          size: 12,
                        ),
                      ),
                    ),
                  // Show "Not Available" indicator for non-playable songs
                  if (!isPlayable)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.block,
                          color: Colors.red,
                          size: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Title and Artist Column - Use Expanded to take available space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.value['title'] ?? 'Unknown',
                      style: TextStyle(
                        color: isPlayable ? Colors.white : Colors.grey[600],
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.value['artist'] ?? widget.album['artist'] ?? 'Unknown Artist',
                      style: TextStyle(
                        color: isPlayable ? Colors.white70 : Colors.grey[500],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Show "Audio not available" message for non-playable songs
                    if (!isPlayable)
                      Text(
                        'Audio not available',
                        style: TextStyle(
                          color: Colors.red[400],
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Duration
              SizedBox(
                width: 80,
                child: Text(
                  _formatDuration(entry.value['duration']),
                  style: TextStyle(
                    color: isPlayable ? Colors.white70 : Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // More options button
              _buildMoreOptionsMenu(entry.value),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSongList() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      margin: EdgeInsets.only(bottom: widget.currentlyPlayingSong != null ? 100 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enhanced Playback Controls
          Container(
            margin: const EdgeInsets.symmetric(vertical: 24),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                      onPressed: _playAll,
                    ),
                  ),
                  const SizedBox(width: 32),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.favorite_border, color: Colors.white70, size: 24),
                      onPressed: () {
                        // TODO: Toggle favorite
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildDownloadButton(),
                  const SizedBox(width: 16),
                  _buildFavoriteButton(),
                  const SizedBox(width: 16),
                  _buildAlbumMoreOptionsMenu(),
                ],
              ),
            ),
          ),

          _buildColumnHeaders(),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isLoading
                ? _buildShimmerLoading()
                : songs.isEmpty
                    ? const Center(
                        child: Text(
                          'No songs found in this album',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          return _buildSongRow(MapEntry(index, songs[index]));
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // Add shimmer loading widget
  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[850]!,
      highlightColor: Colors.grey[700]!,
      child: Column(
        children: List.generate(
          8,
          (index) => Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  // This method is now used directly in the UI with setState

  Future<void> _downloadAlbum() async {
    // Print detailed album information for debugging
    print('AlbumView: Starting download for album ID: ${widget.album['id']}');
    print('AlbumView: Album ID type: ${widget.album['id'].runtimeType}');
    print('AlbumView: Album data: ${widget.album}');

    // Add the album ID to our list of common IDs in the DownloadService
    // This is a temporary solution to help with debugging
    print('IMPORTANT: Add this ID to commonIds in _getDownloadedAlbumIds: "${widget.album['id']}"');

    setState(() {
      _isDownloading = true;
      _totalDownloadProgress = 0.0;
    });

    try {
      // The download service now handles parallel downloading internally
      // and sends progress updates through the stream
      print('AlbumView: Calling downloadAlbum with ${songs.length} songs');
      await _downloadService.downloadAlbum(widget.album, songs);
      print('AlbumView: Download completed successfully');

      // Verify the album is now marked as downloaded
      final isDownloaded = await _downloadService.isAlbumDownloaded(widget.album['id'].toString());
      print('AlbumView: Album download verification: $isDownloaded');

      setState(() {
        _isDownloaded = true;
        _totalDownloadProgress = 1.0;
      });

      // Check if widget is still mounted before showing SnackBar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Album downloaded successfully'),
              ],
            ),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      print('AlbumView: Error downloading album: $e');
      // Check if widget is still mounted before showing SnackBar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download album: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (!_isDownloaded) {
        setState(() => _isDownloading = false);
      }
    }
  }

  // Method to download a single song
  Future<void> _downloadSong(Map<String, dynamic> song) async {
    if (song['audio_url'] == null) {
      _showErrorMessage('Cannot download: Audio URL is missing');
      return;
    }

    print('AlbumView: Starting download for song ID: ${song['id']}');
    
    setState(() {
      _isDownloading = true;
      _totalDownloadProgress = 0.0;
    });

    try {
      // Create a list with just this song for the download service
      final songsList = [song];
      
      // Create a minimal album context for the download service
      final singleSongAlbum = {
        'id': song['id'],
        'title': song['title'],
        'artist': song['artist'] ?? widget.album['artist'] ?? 'Unknown Artist',
        'image_url': song['image_url'] ?? widget.album['image_url'],
      };

      // Download the song
      await _downloadService.downloadAlbum(singleSongAlbum, songsList);
      
      // Check if the song was successfully downloaded
      final isSongDownloaded = await _downloadService.isSongDownloaded(song['id'].toString());
      print('AlbumView: Song download verification: $isSongDownloaded');

      setState(() {
        _totalDownloadProgress = 1.0;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text('${song['title']} downloaded successfully'),
              ],
            ),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      print('AlbumView: Error downloading song: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download song: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Widget _buildDownloadButton() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isDownloaded
          ? Colors.green.withOpacity(0.2)
          : Colors.white.withOpacity(0.1),
      ),
      child: _isDownloading
        ? Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _totalDownloadProgress,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                strokeWidth: 2,
              ),
              Text(
                '${(_totalDownloadProgress * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          )
        : IconButton(
            icon: Icon(
              _isDownloaded ? Icons.download_done : Icons.download_outlined,
              color: _isDownloaded ? Colors.green : Colors.white70,
              size: 24,
            ),
            onPressed: _isDownloaded ? null : _downloadAlbum,
            tooltip: _isDownloaded ? 'Downloaded' : 'Download Album',
          ),
    );
  }

  Widget _buildFavoriteButton() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isFavorited ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.1),
      ),
      child: IconButton(
        icon: Icon(
          _isFavorited ? Icons.favorite : Icons.favorite_border,
          color: _isFavorited ? Colors.green : Colors.white70,
          size: 24,
        ),
        onPressed: _addToFavorites,
        tooltip: _isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dominantColor = _palette?.dominantColor?.color ?? Colors.black;

    // Content to display in both standalone and main layout modes
    Widget content = Stack(
      children: [
        // Background Gradient
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  dominantColor.withOpacity(0.6),
                  Colors.black.withOpacity(0.8),
                  Colors.black,
                ],
                stops: const [0.0, 0.3, 0.7],
              ),
            ),
          ),
        ),
        // Main Scrollable Content
        CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              pinned: true,
              expandedHeight: 300.0, // Adjust as needed
              automaticallyImplyLeading: false, // Remove default back button
              flexibleSpace: FlexibleSpaceBar(
                background: _buildAlbumHeader(),
              ),
              leading: Padding(
                padding: const EdgeInsets.all(8.0),
                child: InkWell(
                  onTap: () {
                    if (widget.inMainLayout && widget.onBackPressed != null) {
                      // Use the callback for in-app navigation
                      widget.onBackPressed!();
                    } else {
                      // Use standard navigation for standalone view
                      Navigator.of(context).pop();
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildSongList(),
            ),
          ],
        ),
      ],
    );

    // If we're in the main layout, wrap content in Material
    // Otherwise, wrap it in a Scaffold
    if (widget.inMainLayout) {
      return Material(
        // Use a transparent color to not affect the background gradient
        color: Colors.transparent,
        child: content,
      );
    } else {
      return Scaffold(
        body: Stack(
          children: [
            content,
            // Queue List (conditionally shown)
            if (showQueue && _currentSong != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + kToolbarHeight, // Adjust top to be below app bar
                right: 0,
                bottom: widget.currentlyPlayingSong != null ? 80.0 : 0, // Space for global player
                child: QueueList(
                  currentSong: _currentSong!,
                  onClose: () => setState(() => showQueue = false),
                  onSongSelected: (song) {
                    // When a song is selected from the queue, play it
                    // and ensure the existing queue context is maintained.
                    final songWithQueue = {
                      ...Map<String, dynamic>.from(song),
                      'queue': _currentSong!['queue'] ?? [], // Preserve the original queue
                    };
                    widget.onSongSelected(songWithQueue); // Call the main play function
                    setState(() {
                      _currentSong = songWithQueue; // Update local _currentSong
                      currentPlayingIndex = songs.indexWhere((s) => s['id'] == song['id']);
                    });
                  },
                ),
              ),
          ],
        ),
      );
    }
  }
}
