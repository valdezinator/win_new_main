import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:supabase/supabase.dart';
import 'dart:async';
import 'dart:ui'; // Add this import for ImageFilter
import 'music_player.dart';
import 'widgets/queue_list.dart';
import 'home_page.dart'; // Add HomeScreen import
import 'services/download_service.dart';
import 'package:cached_network_image/cached_network_image.dart'; // NEW import for caching images

class AlbumView extends StatefulWidget {
  final Map<String, dynamic> album;
  final SupabaseClient supabaseClient;
  final Function(Map<String, dynamic>) onSongSelected;
  final Map<String, dynamic>? currentlyPlayingSong;  // Add this parameter

  const AlbumView({
    Key? key,
    required this.album,
    required this.supabaseClient,
    required this.onSongSelected,
    this.currentlyPlayingSong,  // Add this parameter
  }) : super(key: key);

  @override
  _AlbumViewState createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
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

  @override
  void initState() {
    super.initState();
    _currentSong = widget.currentlyPlayingSong; // initialize with parent's value
    _loadPalette();
    _loadSongs().then((_) {
      if (_currentSong != null) {
        setState(() {
          // Update currentPlayingIndex if needed
          // Assuming that _currentSong exists in songs:
          // (Keep existing logic if desired)
        });
      }
      _checkDownloadState();
    });
    _downloadService.downloadProgress.listen((progress) {
      setState(() => _downloadProgress = progress);
    });
  }

  Future<void> _checkDownloadState() async {
    final isDownloaded = await _downloadService.isAlbumDownloaded(widget.album['id'].toString());
    if (mounted) {
      setState(() {
        _isDownloaded = isDownloaded;
      });
    }
  }

  @override
  void dispose() {
    // Only clear currentPlayingIndex, don't stop the song
    currentPlayingIndex = null;
    super.dispose();
  }

  Future<void> _loadPalette() async {
    if (widget.album['image_url'] != null) {
      final imageProvider = NetworkImage(widget.album['image_url']);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(imageProvider);
      setState(() {
        _palette = paletteGenerator;
      });
    }
  }

  Future<void> _loadSongs() async {
    try {
      print('Loading songs for album ID: ${widget.album['id']}');
      
      final bool isAIPlaylist = (widget.album['is_ai_generated'] ?? false) == true; // default false if missing
      final String tableName = isAIPlaylist ? 'ai_playlists' : 'songs';
      final String idField = isAIPlaylist ? 'playlist_id' : 'album_id';
      
      final response = await widget.supabaseClient
          .from(tableName)
          .select('*')  // Select all fields to ensure we have everything needed
          .eq(idField, widget.album['id']);
      
      print('Response from Supabase: $response');
      
      // Validate audio URLs before setting state
      final validSongs = List<Map<String, dynamic>>.from(response).map((song) {
        print('Song ${song['title']} audio URL: ${song['audio_url']}');
        return song;
      }).toList();
      
      setState(() {
        songs = validSongs;
        isLoading = false;
        
        if (widget.currentlyPlayingSong != null) {
          currentPlayingIndex = songs.indexWhere(
            (song) => song['id'] == widget.currentlyPlayingSong!['id']
          );
          print('Found currently playing song at index: $currentPlayingIndex');
        }
      });
    } catch (e) {
      print('Error loading songs: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  void _playAll() {
    if (songs.isNotEmpty) {
      print('Starting album playback with ${songs.length} songs');
      setState(() {
        currentPlayingIndex = 0;
      });
      _playSong(songs[0]);
    } else {
      print('No songs available to play');
    }
  }

  void _playSong(Map<String, dynamic> song) {
    if (song['audio_url'] == null) {
      print('Error: No audio URL for song ${song['title']}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot play song: Missing audio URL')),
      );
      return;
    }
  
    try {
      // Format queue data first to ensure all songs have required fields
      final formattedQueue = songs.map((s) => {
        ...Map<String, dynamic>.from(s),
        'id': s['id'],
        'title': s['title'] ?? 'Unknown',
        'artist': s['artist'] ?? widget.album['artist'] ?? 'Unknown Artist',
        'audio_url': s['audio_url'],
        'image_url': s['image_url'] ?? widget.album['image_url'],
        'album': widget.album['playlist_name'] ?? widget.album['title'],
        'album_id': widget.album['id'],
      }).toList();

      // Create song context with formatted queue
      final songWithAlbumContext = {
        ...Map<String, dynamic>.from(song),
        'id': song['id'],
        'album': widget.album['playlist_name'] ?? widget.album['title'],
        'album_id': widget.album['id'],
        'album_art': widget.album['image_url'],
        'image_url': song['image_url'] ?? widget.album['image_url'],
        'artist': song['artist'] ?? widget.album['artist'] ?? 'Unknown Artist',
        'title': song['title'] ?? 'Unknown Title',
        'queue': formattedQueue, // Use the formatted queue
      };
      
      print('Playing song with metadata: $songWithAlbumContext');
      print('Queue size: ${formattedQueue.length}');
      
      widget.onSongSelected(songWithAlbumContext);
      
      setState(() {
        _currentSong = songWithAlbumContext; // Store full context including queue
        currentPlayingIndex = songs.indexWhere((s) => s['id'] == song['id']);
      });
    } catch (e) {
      print('Error playing song: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing song: ${e.toString()}')),
      );
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
      child: Row(
        children: [
          const SizedBox(width: 16), // Left margin
          // Track number column
          Container(
            width: 30,
            child: const Text(
              "#",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 20),
          // Song Image space
          const SizedBox(width: 40),
          const SizedBox(width: 16),
          // Title column
          const Expanded(
            flex: 3,
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
          Container(
            width: 80,
            child: const Text(
              "DURATION",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48), // Space for more options
        ],
      ),
    );
  }

  Widget _buildAlbumHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Album Cover with enhanced hover effect
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => isPlayButtonHovered = true),
            onExit: (_) => setState(() => isPlayButtonHovered = false),
            child: Stack(
              children: [
                _buildAlbumCover(),
                // Play button overlay
                if (isPlayButtonHovered)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black.withOpacity(0.5),
                      ),
                      child: Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          // Album Info with refined typography
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.album['category']?.toUpperCase() ?? 'ALBUM',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.album['playlist_name'] ?? widget.album['title'] ?? 'Unknown Album',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      widget.album['artist'] ?? 'Unknown Artist',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Colors.white70,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      '${songs.length} songs',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumCover() {
    return Container(
      width: 200,  // Reduced from 232
      height: 200, // Reduced from 232
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
          ? CachedNetworkImage(
              imageUrl: widget.album['image_url'],
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
                        icon: Icons.favorite_border,
                        text: 'Add Album to Favorites',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Add album to favorites
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
                      ),
                      if (song['downloadable'] == true)
                        _buildMenuItem(
                          icon: Icons.download,
                          text: 'Download',
                          onTap: () {
                            Navigator.pop(context);
                            // TODO: Start download
                          },
                        ),
                      _buildMenuItem(
                        icon: Icons.favorite_border,
                        text: 'Add to Favorites',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: Add to favorites
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 56,
      child: Material(
        color: isHovered ? Colors.white.withOpacity(0.1) : Colors.transparent,
        child: InkWell(
          onTap: () {
            _playSong(entry.value);
          },
          onHover: (hover) {
            setState(() {
              hoveredIndex = hover ? entry.key : null;
            });
          },
          child: Row(
            children: [
              const SizedBox(width: 16),
              // Track Number
              Container(
                width: 30,
                child: Text(
                  '${entry.key + 1}',
                  style: TextStyle(
                    color: isCurrentSong ? Colors.green : Colors.white70,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 20),
              // Song Image
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: entry.value['image_url'] ?? widget.album['image_url'] ?? '',
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
                ),
              ),
              const SizedBox(width: 16),
              // Title and Artist Column
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.value['title'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.value['artist'] ?? widget.album['artist'] ?? 'Unknown Artist',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Duration
              Container(
                width: 80,
                child: Text(
                  _formatDuration(entry.value['duration']),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // More options button
              _buildMoreOptionsMenu(entry.value),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSongList() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      // Add bottom margin to prevent overlap with music player
      margin: EdgeInsets.only(bottom: widget.currentlyPlayingSong != null ? 100 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enhanced Playback Controls
          Container(
            margin: const EdgeInsets.symmetric(vertical: 24),
            child: Row(
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
                _buildAlbumMoreOptionsMenu(),
              ],
            ),
          ),
          
          _buildColumnHeaders(),
          
          // Songs List
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (songs.isEmpty)
            const Center(
              child: Text(
                'No songs found in this album',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...songs.asMap().entries.map((entry) {
              return _buildSongRow(entry);
            }).toList(),
        ],
      ),
    );
  }

  void _toggleQueue(bool show) {
    setState(() {
      showQueue = show;
    });
  }

  Future<void> _downloadAlbum() async {
    setState(() {
      _isDownloading = true;
      _totalDownloadProgress = 0.0;
    });

    try {
      final totalItems = songs.length + 1; // +1 for album cover
      var completedItems = 0;

      // Listen to individual file progress
      _downloadService.downloadProgress.listen((progress) {
        final currentItemProgress = progress.values.first;
        setState(() {
          _totalDownloadProgress = (completedItems + currentItemProgress) / totalItems;
        });
      });

      await _downloadService.downloadAlbum(widget.album, songs);
      
      setState(() {
        _isDownloaded = true;
        _totalDownloadProgress = 1.0;
      });

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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download album: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!_isDownloaded) {
        setState(() => _isDownloading = false);
      }
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

  @override
  Widget build(BuildContext context) {
    final dominantColor = _palette?.dominantColor?.color ?? Colors.black;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color:  Color(0xFF0C0F14),  // Solid dark background
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.8,
                  colors: [
                    dominantColor.withOpacity(0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.8],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomRight,
                    radius: 1.8,
                    colors: [
                      (_palette?.vibrantColor?.color ?? dominantColor).withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.8],
                  ),
                ),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        // Navigation Sidebar
                        SizedBox(
                          width: 232,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 108),
                            child: Material(
                              elevation: 8,
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(15),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.1),
                                    width: 1,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withOpacity(0.1),
                                      Colors.white.withOpacity(0.05),
                                    ],
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const SizedBox(height: 40),
                                    _buildNavItem(Icons.home, 'Home'),
                                    _buildNavItem(Icons.search, 'Search'),
                                    _buildNavItem(Icons.library_music, 'Library'),
                                    _buildNavItem(Icons.person, 'Profile'),
                                    const Spacer(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Main content area
                        Expanded(
                          child: Column(
                            children: [
                              // Back button row at top
                              Container(
                                padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                                child: Row(
                                  children: [
                                    InkWell(
                                      onTap: () => Navigator.pop(context),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.arrow_back, color: Colors.white, size: 24),
                                            SizedBox(width: 8),
                                            Text(
                                              'Back',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Content area
                              Expanded(
                                child: SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  child: Column(
                                    children: [
                                      _buildAlbumHeader(),
                                      _buildSongList(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Music player overlay at bottom in album view
                    if (_currentSong != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Show queue if visible
                            if (showQueue)
                              QueueList(
                                currentSong: _currentSong!,
                                onClose: () => _toggleQueue(false),
                              ),
                            // Music player
                            MusicPlayer(
                              key: ValueKey(_currentSong!['id']),
                              song: _currentSong!,
                              showQueue: showQueue,
                              onQueueToggle: _toggleQueue,  // Add this line
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String text, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap ?? () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white.withOpacity(0.1),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.05),
              ],
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}