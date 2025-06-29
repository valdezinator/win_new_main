import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart';
import 'music_player.dart';
import 'widgets/queue_list.dart';
import 'dart:math';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'services/backblaze_service.dart';
import 'services/analytics_service.dart';
import 'layouts/content_view.dart'; // Import ContentViewController

class BrowseScreen extends StatefulWidget {
  final SupabaseClient supabaseClient;
  final Function(Map<String, dynamic>) onSongSelected;
  final Map<String, dynamic>? currentlyPlayingSong;

  const BrowseScreen({
    super.key,
    required this.supabaseClient,
    required this.onSongSelected,
    this.currentlyPlayingSong,
  });

  @override
   State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  Map<String, List<Map<String, dynamic>>> categorizedResults = {};
  bool isSearching = false;
  List<Map<String, dynamic>> albums = [];
  bool isLoading = true;
  int? currentPlayingIndex;
  bool showQueue = false;
  Timer? _debounce;
  int _keyboardSelectedIndex = -1;
  FocusNode _searchFocusNode = FocusNode();
  final BackblazeService _backblazeService = BackblazeService();
  final AnalyticsService _analyticsService = AnalyticsService();

  // Browse content data
  List<Map<String, dynamic>> featuredAlbums = [];
  List<Map<String, dynamic>> recentlyPlayed = [];
  List<Map<String, dynamic>> topCharts = [];
  List<Map<String, dynamic>> newReleases = [];
  List<Map<String, dynamic>> trendingArtists = [];
  List<Map<String, dynamic>> popularPlaylists = [];
  List<Map<String, dynamic>> genres = [];
  Map<String, List<Map<String, dynamic>>> genreAlbums = {};

  // Tab controller for the search results tabs
  // late TabController _tabController;
  // int _selectedTabIndex = 0;

  // Replace TabBar with chip filters
  final List<String> _filters = ['All', 'Songs', 'Artists', 'Albums', 'Playlists'];
  int _selectedFilterIndex = 0;

  // Hover state for song items
  int? _hoveredSongIndex;

  final Map<String, Map<String, dynamic>> _songCache = {};

  @override
  void initState() {
    super.initState();
    // Remove TabController initialization
    // _tabController = TabController(length: 5, vsync: this);
    // _tabController.addListener(() {
    //   if (!_tabController.indexIsChanging) {
    //     setState(() {
    //       _selectedTabIndex = _tabController.index;
    //     });
    //   }
    // });
    _loadBrowseContent();
    // Initialize current playing index if a song is playing
    if (widget.currentlyPlayingSong != null) {
      _updateCurrentPlayingIndex();
    }
  }

  @override
  void dispose() {
    // Remove _tabController.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadBrowseContent() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Load all data in parallel
      await Future.wait([
        _loadAlbums(),
        _loadFeaturedAlbums(),
        _loadRecentlyPlayed(),
        _loadTopCharts(),
        _loadNewReleases(),
        _loadTrendingArtists(),
        _loadPopularPlaylists(),
        _loadGenres(),
      ]);

      // Load genre-specific albums after genres are loaded
      await _loadGenreAlbums();

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Error loading browse content: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadAlbums() async {
    try {
      final response = await widget.supabaseClient
          .from('albums')
          .select()
          .order('created_at');

      setState(() {
        albums = List<Map<String, dynamic>>.from(response);
        // Cache all songs in albums if available
        for (var album in albums) {
          if (album['songs'] != null) {
            for (var song in album['songs']) {
              _songCache[song['id'].toString()] = song;
            }
          }
        }
      });
    } catch (e) {
      print('Error loading albums: $e');
    }
  }

  Future<void> _loadFeaturedAlbums() async {
    try {
      final response = await widget.supabaseClient
          .from('albums')
          .select()
          .eq('featured', true)
          .order('created_at', ascending: false)
          .limit(10);

      setState(() {
        featuredAlbums = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error loading featured albums: $e');
    }
  }

  Future<void> _loadRecentlyPlayed() async {
    try {
      // For now, we'll use the most recent albums as recently played
      // In a real app, this would come from user listening history
      final response = await widget.supabaseClient
          .from('albums')
          .select()
          .order('created_at', ascending: false)
          .limit(8);

      setState(() {
        recentlyPlayed = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error loading recently played: $e');
    }
  }

  Future<void> _loadTopCharts() async {
    try {
      // For now, we'll use albums with the most songs as top charts
      // In a real app, this would be based on actual play counts
      final response = await widget.supabaseClient
          .from('albums')
          .select()
          .order('created_at', ascending: false)
          .limit(6);

      setState(() {
        topCharts = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error loading top charts: $e');
    }
  }

  Future<void> _loadNewReleases() async {
    try {
      final response = await widget.supabaseClient
          .from('albums')
          .select()
          .order('created_at', ascending: false)
          .limit(8);

      setState(() {
        newReleases = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error loading new releases: $e');
    }
  }

  Future<void> _loadTrendingArtists() async {
    try {
      final response = await widget.supabaseClient
          .from('artists')
          .select()
          .order('created_at', ascending: false)
          .limit(6);

      setState(() {
        trendingArtists = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error loading trending artists: $e');
    }
  }

  Future<void> _loadPopularPlaylists() async {
    try {
      // For now, we'll create mock playlists
      // In a real app, this would come from a playlists table
      setState(() {
        popularPlaylists = [
          {
            'id': '1',
            'title': 'Today\'s Top Hits',
            'description': 'The hottest tracks right now',
            'image_url': null,
            'track_count': 50,
          },
          {
            'id': '2',
            'title': 'Chill Vibes',
            'description': 'Relaxing music for your day',
            'image_url': null,
            'track_count': 35,
          },
          {
            'id': '3',
            'title': 'Workout Mix',
            'description': 'High energy tracks for your workout',
            'image_url': null,
            'track_count': 40,
          },
          {
            'id': '4',
            'title': 'Late Night',
            'description': 'Perfect for late night listening',
            'image_url': null,
            'track_count': 30,
          },
        ];
      });
    } catch (e) {
      print('Error loading popular playlists: $e');
    }
  }

  Future<void> _loadGenres() async {
    try {
      // For now, we'll create mock genres
      // In a real app, this would come from a genres table
      setState(() {
        genres = [
          {'id': '1', 'name': 'Pop', 'color': Colors.pink},
          {'id': '2', 'name': 'Rock', 'color': Colors.red},
          {'id': '3', 'name': 'Hip Hop', 'color': Colors.orange},
          {'id': '4', 'name': 'Electronic', 'color': Colors.purple},
          {'id': '5', 'name': 'Jazz', 'color': Colors.blue},
          {'id': '6', 'name': 'Classical', 'color': Colors.indigo},
          {'id': '7', 'name': 'Country', 'color': Colors.green},
          {'id': '8', 'name': 'R&B', 'color': Colors.teal},
        ];
      });
    } catch (e) {
      print('Error loading genres: $e');
    }
  }

  Future<void> _loadGenreAlbums() async {
    try {
      for (var genre in genres) {
        // For now, we'll use random albums for each genre
        // In a real app, this would be filtered by actual genre tags
        final response = await widget.supabaseClient
            .from('albums')
            .select()
            .order('created_at', ascending: false)
            .limit(6);

        setState(() {
          genreAlbums[genre['name']] = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('Error loading genre albums: $e');
    }
  }

  void _updateCurrentPlayingIndex() {
    if (widget.currentlyPlayingSong == null) return;

    // Find the song in the current albums list
    for (var album in albums) {
      if (album['id'] == widget.currentlyPlayingSong?['album_id']) {
        setState(() {
          currentPlayingIndex = albums.indexOf(album);
        });
        break;
      }
    }
  }

  @override
  void didUpdateWidget(BrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentlyPlayingSong?.isNotEmpty != oldWidget.currentlyPlayingSong?.isNotEmpty ||
        widget.currentlyPlayingSong?['id'] != oldWidget.currentlyPlayingSong?['id']) {
      _updateCurrentPlayingIndex();
    }
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(value);
    });
    setState(() {
      isSearching = true;
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        categorizedResults = {};
        isSearching = false;
      });
      return;
    }
    
    setState(() {
      isSearching = true;
    });
    
    try {
      final songsFuture = widget.supabaseClient
          .from('songs_2')
          .select()
          .ilike('title', '%$query%');
      final albumsFuture = widget.supabaseClient
          .from('albums')
          .select()
          .ilike('title', '%$query%');
      final artistsFuture = widget.supabaseClient
          .from('artists')
          .select()
          .ilike('name', '%$query%');

      final results = await Future.wait([songsFuture, albumsFuture, artistsFuture]);

      final songs = List<Map<String, dynamic>>.from(results[0]).map((song) {
        return {
          ...song,
          'isPlaying': widget.currentlyPlayingSong != null &&
                       widget.currentlyPlayingSong!['id'] == song['id'],
        };
      }).toList();

      setState(() {
        categorizedResults = {
          'Songs': songs,
          'Albums': List<Map<String, dynamic>>.from(results[1]),
          'Artists': List<Map<String, dynamic>>.from(results[2]),
        };
        isSearching = false;
      });
      
      // Log search event
      _analyticsService.logSearch(
        query: query,
        resultCount: categorizedResults['Songs']?.length ?? 0,
        resultType: 'song',
      );
      
    } catch (e) {
      setState(() {
        isSearching = false;
      });
      
      // Log search error
      _analyticsService.logEvent(
        'search_error',
        parameters: {
          'query': query,
          'error': e.toString(),
        },
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error performing search: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSearchAlbumCard(Map<String, dynamic> album) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          // Navigate to album view
        },
        child: SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album Cover
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: album['image_url'] != null
                        ? Image.network(
                            album['image_url'],
                            width: 160,
                            height: 160,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 160,
                            height: 160,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 60, color: Colors.white),
                          ),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          // Navigate to album view
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Album Title
              Text(
                album['title'] ?? 'Unknown Album',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),              // Artist Name
              Text(
                album['artist'] ?? 'Unknown Artist',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchArtistCircle(Map<String, dynamic> artist) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          // Navigate to artist view
        },
        child: Column(
          children: [
            // Artist Image
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: artist['image_url'] != null ? NetworkImage(artist['image_url']) : null,
                  backgroundColor: Colors.grey[850],
                  child: artist['image_url'] == null ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(50),
                      onTap: () {
                        // Navigate to artist view
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Artist Name
            SizedBox(
              width: 100,
              child: Text(
                artist['name'] ?? 'Unknown Artist',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _playSearchResult(Map<String, dynamic> song) async {
    try {
      final songId = song['id'].toString();
      Map<String, dynamic> songData = song;
      if (_songCache.containsKey(songId)) {
        songData = _songCache[songId]!;
      }
      final audioUrl = await _backblazeService.getAudioUrl(
        songData['audio_url'],
        songData['file_identifier'],
      );
      print('Resolved audio URL (BrowseScreen): $audioUrl');
      final songWithSearchContext = {
        ...Map<String, dynamic>.from(songData),
        'queue': categorizedResults['Songs'] ?? [],  // Use search results as queue
        'isPlaying': true,
        'audio_url': audioUrl,
      };
      widget.onSongSelected(songWithSearchContext);
    } catch (e) {
      print('Error resolving audio URL (BrowseScreen): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing song: ${e.toString()}')),
        );
      }
    }
  }

  void _toggleQueue(bool show) {
    setState(() {
      showQueue = show;
    });
  }

  Widget _buildBrowseCard(String title, List<Color> colors, IconData icon) {
    return Container(
      width: 140,  // Reduced from 180
      height: 140, // Reduced from 180
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6), // Smaller radius
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -15, // Adjusted position
            bottom: -8,  // Adjusted position
            child: Transform.rotate(
              angle: 0.4,
              child: Icon(
                icon,
                size: 70, // Reduced from 100
                color: Colors.black.withOpacity(0.4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12), // Reduced padding
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16, // Reduced from 20
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResult(Map<String, dynamic> song, bool isCurrentlyPlaying, {int? index, bool compact = false}) {
    final isHovered = index != null && _hoveredSongIndex == index;
    final isKeyboardSelected = index != null && _keyboardSelectedIndex == index;

    return MouseRegion(
      onEnter: (_) {
        if (index != null) {
          setState(() => _hoveredSongIndex = index);
        }
      },
      onExit: (_) {
        if (index != null && _hoveredSongIndex == index) {
          setState(() => _hoveredSongIndex = null);
        }
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onSecondaryTapDown: (details) async {
          final selected = await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx + 1,
              details.globalPosition.dy + 1,
            ),
            items: [
              const PopupMenuItem<String>(value: 'play', child: Text('Play Now')),
              const PopupMenuItem<String>(value: 'add_to_queue', child: Text('Add to Queue')),
              const PopupMenuItem<String>(value: 'add_to_playlist', child: Text('Add to Playlist')),
              const PopupMenuItem<String>(value: 'view_album', child: Text('View Album')),
              const PopupMenuItem<String>(value: 'view_artist', child: Text('View Artist')),
            ],
          );
          if (selected == 'play') {
            _playSearchResult(song);
          } else if (selected == 'add_to_queue') {
            _addToQueue(song);
          } else if (selected == 'add_to_playlist') {
            _showAddToPlaylistDialog(song);
          } else if (selected == 'view_album') {
            _navigateToAlbum({'id': song['album_id'], 'title': song['album'] ?? 'Album'});
          } else if (selected == 'view_artist') {
            _navigateToArtist({'id': song['artist_id'], 'name': song['artist'] ?? 'Artist'});
          }
        },
        child: Container(
          margin: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
          decoration: BoxDecoration(
            color: isKeyboardSelected
                ? Colors.green.withOpacity(0.15)
                : isHovered
                    ? Colors.white.withOpacity(0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            dense: compact,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: compact ? 4 : 8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: SizedBox(
              width: compact ? 40 : 48,
              height: compact ? 40 : 48,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: FutureBuilder<String>(
                      future: _backblazeService.getImageUrl(
                        song['image_url'],
                        song['file_identifier'],
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            color: Colors.grey[850],
                            child: Icon(
                              Icons.music_note,
                              color: Colors.white,
                              size: compact ? 20 : 24,
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return Container(
                            color: Colors.grey[850],
                            child: Icon(
                              Icons.music_note,
                              color: Colors.white,
                              size: compact ? 20 : 24,
                            ),
                          );
                        }
                        return Image.network(
                          snapshot.data!,
                          width: compact ? 40 : 48,
                          height: compact ? 40 : 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[850],
                            child: Icon(
                              Icons.music_note,
                              color: Colors.white,
                              size: compact ? 20 : 24,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (isCurrentlyPlaying)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.green,
                          size: compact ? 20 : 24,
                        ),
                      ),
                    ),
                  if (isHovered && !isCurrentlyPlaying)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: compact ? 20 : 24,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            title: _highlightMatch(song['title'] ?? '', _searchController.text),
            subtitle: _highlightMatch(song['artist'] ?? 'Unknown Artist', _searchController.text),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isHovered && !compact)
                  IconButton(
                    icon: Icon(
                      Icons.favorite_border,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 20,
                  ),
                if (isHovered && !compact)
                  const SizedBox(width: 16),
                Text(
                  _formatDuration(song['duration']),
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: compact ? 12 : 14,
                  ),
                ),
                if (isHovered) ...[
                  const SizedBox(width: 16),
                  IconButton(
                    icon: Icon(
                      Icons.more_horiz,
                      color: Colors.grey[400],
                      size: compact ? 16 : 20,
                    ),
                    onPressed: () async {
                      final RenderBox box = context.findRenderObject() as RenderBox;
                      final Offset position = box.localToGlobal(Offset.zero);
                      final selected = await showMenu<String>(
                        context: context,
                        position: RelativeRect.fromLTRB(
                          position.dx + 40,
                          position.dy + 40,
                          position.dx + 41,
                          position.dy + 41,
                        ),
                        items: [
                          const PopupMenuItem<String>(value: 'play', child: Text('Play Now')),
                          const PopupMenuItem<String>(value: 'add_to_queue', child: Text('Add to Queue')),
                          const PopupMenuItem<String>(value: 'add_to_playlist', child: Text('Add to Playlist')),
                          const PopupMenuItem<String>(value: 'view_album', child: Text('View Album')),
                          const PopupMenuItem<String>(value: 'view_artist', child: Text('View Artist')),
                        ],
                      );
                      if (selected == 'play') {
                        _playSearchResult(song);
                      } else if (selected == 'add_to_queue') {
                        _addToQueue(song);
                      } else if (selected == 'add_to_playlist') {
                        _showAddToPlaylistDialog(song);
                      } else if (selected == 'view_album') {
                        _navigateToAlbum({'id': song['album_id'], 'title': song['album'] ?? 'Album'});
                      } else if (selected == 'view_artist') {
                        _navigateToArtist({'id': song['artist_id'], 'name': song['artist'] ?? 'Artist'});
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: compact ? 16 : 20,
                  ),
                ],
              ],
            ),
            onTap: () => _playSearchResult(song),
          ),
        ),
      ),
    );
  }

  String _formatDuration(dynamic duration) {
    if (duration == null) return '0:00';
    if (duration is int) {
      final minutes = duration ~/ 60;
      final seconds = duration % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return duration.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // Search Bar with Chips
            Container(
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: SvgPicture.asset(
                              'assets/icons/browse_icon.svg',
                              width: 24,
                              height: 24,
                            ),
                          ),
                          Expanded(
                            child: RawKeyboardListener(
                              focusNode: _searchFocusNode,
                              onKey: (event) {
                                if (event is RawKeyDownEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                    setState(() {
                                      _keyboardSelectedIndex = (_keyboardSelectedIndex + 1) % (categorizedResults['Songs']?.length ?? 1);
                                    });
                                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                    setState(() {
                                      _keyboardSelectedIndex = (_keyboardSelectedIndex - 1);
                                      if (_keyboardSelectedIndex < 0) _keyboardSelectedIndex = (categorizedResults['Songs']?.length ?? 1) - 1;
                                    });
                                  } else if (event.logicalKey == LogicalKeyboardKey.enter && _keyboardSelectedIndex >= 0) {
                                    final songs = categorizedResults['Songs'] ?? [];
                                    if (_keyboardSelectedIndex < songs.length) {
                                      _playSearchResult(songs[_keyboardSelectedIndex]);
                                    }
                                  }
                                }
                              },
                              child: TextField(
                                controller: _searchController,
                                style: GoogleFonts.montserrat(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'What do you want to listen to?',
                                  hintStyle: GoogleFonts.montserrat(
                                    color: Colors.grey[400],
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.fromLTRB(0, 15, 16, 12),
                                ),
                                onChanged: _onSearchChanged,
                              ),
                            ),
                          ),
                          if (isSearching)
                            Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.7)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Chip Filters
                  if (_searchController.text.isNotEmpty)
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: _filters.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final selected = _selectedFilterIndex == idx;
                          return ChoiceChip(
                            label: Text(
                              _filters[idx],
                              style: TextStyle(
                                color: selected ? Colors.white : const Color.fromARGB(255, 0, 0, 0),
                                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            selected: selected,
                            selectedColor: Colors.green,
                            backgroundColor: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.08),
                            onSelected: (val) {
                              setState(() {
                                _selectedFilterIndex = idx;
                              });
                            },
                            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _searchController.text.isEmpty
                  ? _buildBrowseContent()
                  : isSearching
                    ? _buildShimmerLoader()
                    : _buildSearchResults(),
              ),
            ),
          ],
        ),

        // Add gradient overlay for floating player
        if (widget.currentlyPlayingSong != null) ...[
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 92, // Updated height to match new player + margins
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
          if (showQueue)
            Positioned(
              bottom: 92,
              left: 0,
              right: 0,
              child: QueueList(
                currentSong: widget.currentlyPlayingSong!,
                onClose: () => _toggleQueue(false),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: MusicPlayer(
              key: ValueKey('player_${widget.currentlyPlayingSong!['id']}'),
              song: widget.currentlyPlayingSong!,
              onQueueToggle: _toggleQueue,
              showQueue: showQueue,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBrowseContent() {
    if (isLoading) {
      return _buildShimmerLoader();
    }

    // Calculate bottom padding based on whether music player is visible
    final bottomPadding = widget.currentlyPlayingSong != null ? 120.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24.0, 24.0, 24.0, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Section
          _buildWelcomeSection(),
          const SizedBox(height: 32),

          // Featured Albums
          if (featuredAlbums.isNotEmpty) ...[
            _buildSectionHeader('Featured Albums', Icons.star),
            const SizedBox(height: 16),
            _buildAlbumGrid(featuredAlbums),
            const SizedBox(height: 32),
          ],

          // Recently Played
          if (recentlyPlayed.isNotEmpty) ...[
            _buildSectionHeader('Recently Played', Icons.history),
            const SizedBox(height: 16),
            _buildAlbumGrid(recentlyPlayed),
            const SizedBox(height: 32),
          ],

          // Top Charts
          if (topCharts.isNotEmpty) ...[
            _buildSectionHeader('Top Charts', Icons.trending_up),
            const SizedBox(height: 16),
            _buildTopChartsSection(),
            const SizedBox(height: 32),
          ],

          // New Releases
          if (newReleases.isNotEmpty) ...[
            _buildSectionHeader('New Releases', Icons.new_releases),
            const SizedBox(height: 16),
            _buildAlbumGrid(newReleases),
            const SizedBox(height: 32),
          ],

          // Trending Artists
          if (trendingArtists.isNotEmpty) ...[
            _buildSectionHeader('Trending Artists', Icons.person),
            const SizedBox(height: 16),
            _buildArtistGrid(trendingArtists),
            const SizedBox(height: 32),
          ],

          // Popular Playlists
          if (popularPlaylists.isNotEmpty) ...[
            _buildSectionHeader('Popular Playlists', Icons.playlist_play),
            const SizedBox(height: 16),
            _buildPlaylistGrid(popularPlaylists),
            const SizedBox(height: 32),
          ],

          // Browse by Genre
          if (genres.isNotEmpty) ...[
            _buildSectionHeader('Browse by Genre', Icons.category),
            const SizedBox(height: 16),
            _buildGenreGrid(),
            const SizedBox(height: 32),
          ],

          // Genre-specific sections
          ...genres.map((genre) {
            final genreAlbumsList = genreAlbums[genre['name']] ?? [];
            if (genreAlbumsList.isNotEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('${genre['name']} Music', Icons.music_note),
                  const SizedBox(height: 16),
                  _buildAlbumGrid(genreAlbumsList),
                  const SizedBox(height: 32),
                ],
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1DB954),
            const Color(0xFF1ed760),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good ${_getGreeting()}!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Discover new music and explore your favorite artists',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.music_note,
              color: Colors.white,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.green,
          size: 24,
        ),
        const SizedBox(width: 12),
        Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumGrid(List<Map<String, dynamic>> albums) {
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) => _buildBrowseAlbumCard(albums[index]),
      ),
    );
  }

  Widget _buildBrowseAlbumCard(Map<String, dynamic> album) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _navigateToAlbum(album),
        child: SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album Cover
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FutureBuilder<String>(
                      future: _backblazeService.getImageUrl(
                        album['image_url'],
                        album['file_identifier'],
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            width: 160,
                            height: 180,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 60, color: Colors.white),
                          );
                        }
                        if (snapshot.hasError || !snapshot.hasData) {
                          return Container(
                            width: 160,
                            height: 180,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 60, color: Colors.white),
                          );
                        }
                        return Image.network(
                          snapshot.data!,
                          width: 160,
                          height: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 160,
                            height: 180,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 60, color: Colors.white),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _navigateToAlbum(album),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Album Title
              Text(
                album['title'] ?? 'Unknown Album',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Artist Name
              Text(
                album['artist'] ?? 'Unknown Artist',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopChartsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ...topCharts.asMap().entries.map((entry) {
            final index = entry.key;
            final album = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  // Rank
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: index < 3 ? const Color(0xFF1DB954) : Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Album Cover
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: FutureBuilder<String>(
                      future: _backblazeService.getImageUrl(
                        album['image_url'],
                        album['file_identifier'],
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 24, color: Colors.white),
                          );
                        }
                        if (snapshot.hasError || !snapshot.hasData) {
                          return Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 24, color: Colors.white),
                          );
                        }
                        return Image.network(
                          snapshot.data!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 24, color: Colors.white),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Album Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          album['artist'] ?? 'Unknown Artist',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Play Button
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    onPressed: () => _navigateToAlbum(album),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildArtistGrid(List<Map<String, dynamic>> artists) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: artists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 24),
        itemBuilder: (context, index) => _buildBrowseArtistCircle(artists[index]),
      ),
    );
  }

  Widget _buildPlaylistGrid(List<Map<String, dynamic>> playlists) {
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) => _buildPlaylistCard(playlists[index]),
      ),
    );
  }

  Widget _buildPlaylistCard(Map<String, dynamic> playlist) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _navigateToPlaylist(playlist),
        child: SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Playlist Cover
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.grey[800]!,
                            Colors.grey[900]!,
                          ],
                        ),
                      ),
                      child: const Icon(Icons.playlist_play, size: 60, color: Colors.white),
                    ),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _navigateToPlaylist(playlist),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Playlist Title
              Text(
                playlist['title'] ?? 'Unknown Playlist',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Playlist Description
              Text(
                playlist['description'] ?? '',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenreGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: genres.length,
      itemBuilder: (context, index) => _buildGenreCard(genres[index]),
    );
  }

  Widget _buildGenreCard(Map<String, dynamic> genre) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _navigateToGenre(genre),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                genre['color'] as Color,
                (genre['color'] as Color).withOpacity(0.7),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -10,
                bottom: -10,
                child: Transform.rotate(
                  angle: 0.3,
                  child: Icon(
                    Icons.music_note,
                    size: 60,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      genre['name'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Navigation methods
  void _navigateToAlbum(Map<String, dynamic> album) {
    // Navigate to album view using ContentViewController
    ContentViewController().navigateTo(
      ContentType.album,
      data: album,
    );
  }

  void _navigateToArtist(Map<String, dynamic> artist) {
    // Navigate to artist view using ContentViewController
    ContentViewController().navigateTo(
      ContentType.artist,
      data: artist,
    );
  }

  void _navigateToPlaylist(Map<String, dynamic> playlist) {
    // Navigate to playlist view using ContentViewController
    ContentViewController().navigateTo(
      ContentType.playlist,
      data: playlist,
    );
  }

  void _navigateToGenre(Map<String, dynamic> genre) {
    // Navigate to genre view - for now just show a snackbar since genre view isn't implemented
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening genre: ${genre['name']}')),
    );
  }

  Widget _buildShimmerLoader() {
    // Calculate bottom padding based on whether music player is visible
    final bottomPadding = widget.currentlyPlayingSong != null ? 120.0 : 24.0;

    // Simple shimmer/skeleton loader for search results
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(24.0, 24.0, 24.0, bottomPadding),
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _highlightMatch(String text, String query) {
    if (query.isEmpty) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white));
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);
    if (matchIndex == -1) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white));
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(text: text.substring(0, matchIndex), style: const TextStyle(color: Colors.white)),
          TextSpan(text: text.substring(matchIndex, matchIndex + query.length), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          TextSpan(text: text.substring(matchIndex + query.length), style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (categorizedResults.isEmpty) {
      return _buildEmptySearchState();
    }

    // Show content based on selected chip
    switch (_filters[_selectedFilterIndex]) {
      case 'Songs':
        return _buildSongsTab();
      case 'Artists':
        return _buildArtistsTab();
      case 'Albums':
        return _buildAlbumsTab();
      case 'Playlists':
        return _buildPlaylistsTab();
      case 'All':
      default:
        return _buildAllResultsTab();
    }
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 24),
          Text(
            'No results found for "${_searchController.text}"',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for something else',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllResultsTab() {
    // Calculate bottom padding based on whether music player is visible
    final bottomPadding = widget.currentlyPlayingSong != null ? 120.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(32.0, 24.0, 32.0, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Result Section - Full Width Hero Card
          if ((categorizedResults['Songs']?.isNotEmpty ?? false) ||
              (categorizedResults['Albums']?.isNotEmpty ?? false) ||
              (categorizedResults['Artists']?.isNotEmpty ?? false)) ...[
            _buildTopResultSection(),
            const SizedBox(height: 40),
          ],

          // Main Content Grid - 2 Column Layout for Desktop
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Left Column - Songs and Artists
                Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Songs Section
                    if (categorizedResults['Songs']?.isNotEmpty ?? false) ...[
                      _buildSectionHeader('Songs', Icons.music_note),
                      const SizedBox(height: 16),
                      _buildSongsList(categorizedResults['Songs']!),
                      const SizedBox(height: 32),
                    ],

                    // Artists Section
                    if (categorizedResults['Artists']?.isNotEmpty ?? false) ...[
                      _buildSectionHeader('Artists', Icons.person),
                      const SizedBox(height: 16),
                      _buildArtistsGrid(categorizedResults['Artists']!),
                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 32),

              // Right Column - Albums and Additional Content
                Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Albums Section
                    if (categorizedResults['Albums']?.isNotEmpty ?? false) ...[
                      _buildSectionHeader('Albums', Icons.album),
                      const SizedBox(height: 16),
                      _buildAlbumsGrid(categorizedResults['Albums']!),
                      const SizedBox(height: 32),
                    ],

                    // Quick Actions Section
                    _buildQuickActionsSection(),
                  ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTopResultSection() {
    final song = (categorizedResults['Songs']?.isNotEmpty ?? false) ? categorizedResults['Songs']![0] : null;
    final artist = (categorizedResults['Artists']?.isNotEmpty ?? false) ? categorizedResults['Artists']![0] : null;
    final album = (categorizedResults['Albums']?.isNotEmpty ?? false) ? categorizedResults['Albums']![0] : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green.withOpacity(0.1),
            Colors.green.withOpacity(0.05),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.green.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Left side - Image and basic info
            if (song != null) ...[
              _buildTopResultImage(song, 120),
                const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Song Title
                    Text(
                      song['title'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Artist Name
                    Text(
                      song['artist'] ?? 'Unknown Artist',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Song Type and Duration
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'SONG',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _formatDuration(song['duration']),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                    ),
                  ),
              ],
            ),
                  ],
                ),
              ),
            ] else if (artist != null) ...[
              _buildTopResultArtistImage(artist, 120),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Artist Name
                    Text(
                      artist['name'] ?? 'Unknown Artist',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Artist Type
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'ARTIST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (album != null) ...[
              _buildTopResultImage(album, 120),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Album Title
                    Text(
                      album['title'] ?? 'Unknown Album',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Artist Name
                    Text(
                      album['artist'] ?? 'Unknown Artist',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Album Type
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'ALBUM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
              ),
            ),
          ],
                ),
            ),
          ],
        ],
        ),
      ),
    );
  }

  Widget _buildTopResultImage(Map<String, dynamic> item, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<String>(
        future: _backblazeService.getImageUrl(
          item['image_url'],
          item['file_identifier'],
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              width: size,
              height: size,
              color: Colors.grey[850],
              child: const Icon(Icons.music_note, size: 50, color: Colors.white),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Container(
              width: size,
              height: size,
              color: Colors.grey[850],
              child: const Icon(Icons.music_note, size: 50, color: Colors.white),
            );
          }
          return Image.network(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey[850],
              child: const Icon(Icons.music_note, size: 50, color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopResultArtistImage(Map<String, dynamic> artist, double size) {
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: artist['image_url'] != null ? NetworkImage(artist['image_url']) : null,
      backgroundColor: Colors.grey[850],
      child: artist['image_url'] == null ? Icon(Icons.person, size: size / 2, color: Colors.white) : null,
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: primary ? Colors.green : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: primary ? null : Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: primary ? Colors.white : Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: primary ? Colors.white : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSongsList(List<Map<String, dynamic>> songs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: songs.take(5).map((song) => _buildDesktopSongItem(song)).toList(),
      ),
    );
  }

  Widget _buildDesktopSongItem(Map<String, dynamic> song) {
    final isCurrentlyPlaying = song['isPlaying'] == true;
    final songs = categorizedResults['Songs'] ?? [];
    final isHovered = _hoveredSongIndex == songs.indexOf(song);

      return MouseRegion(
      onEnter: (_) => setState(() => _hoveredSongIndex = songs.indexOf(song)),
      onExit: (_) => setState(() => _hoveredSongIndex = null),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _playSearchResult(song),
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
            color: isCurrentlyPlaying
                ? Colors.green.withOpacity(0.1)
                : isHovered
                    ? Colors.white.withOpacity(0.05)
                    : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
              // Album Art
                ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: FutureBuilder<String>(
                  future: _backblazeService.getImageUrl(
                    song['image_url'],
                    song['file_identifier'],
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        width: 48,
                        height: 48,
                          color: Colors.grey[850],
                        child: const Icon(Icons.music_note, size: 24, color: Colors.white),
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey[850],
                        child: const Icon(Icons.music_note, size: 24, color: Colors.white),
                      );
                    }
                    return Image.network(
                      snapshot.data!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey[850],
                        child: const Icon(Icons.music_note, size: 24, color: Colors.white),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              
                // Song Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song['title'] ?? 'Unknown',
                      style: TextStyle(
                        color: isCurrentlyPlaying ? Colors.green : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                      Text(
                        song['artist'] ?? 'Unknown Artist',
                        style: TextStyle(
                          color: Colors.grey[400],
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Duration
                          Text(
                            _formatDuration(song['duration']),
                            style: TextStyle(
                  color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
              
              const SizedBox(width: 16),
              
              // Actions
              if (isHovered || isCurrentlyPlaying)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                        color: isCurrentlyPlaying ? Colors.green : Colors.white,
                        size: 20,
                      ),
                      onPressed: () => _playSearchResult(song),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 20,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.favorite_border,
                        color: Colors.grey[400],
                        size: 18,
                      ),
                      onPressed: () {},
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 18,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.more_horiz,
                        color: Colors.grey[400],
                        size: 18,
                      ),
                      onPressed: () => _showSongContextMenu(song),
                    padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 18,
                  ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildArtistsGrid(List<Map<String, dynamic>> artists) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) => _buildDesktopArtistCard(artists[index]),
    );
  }

  Widget _buildDesktopArtistCard(Map<String, dynamic> artist) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
        onTap: () => _navigateToArtist(artist),
          child: Container(
            decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: artist['image_url'] != null ? NetworkImage(artist['image_url']) : null,
                  backgroundColor: Colors.grey[850],
                  child: artist['image_url'] == null ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                ),
              const SizedBox(height: 16),
                      Text(
                        artist['name'] ?? 'Unknown Artist',
                        style: const TextStyle(
                          color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                        ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: const Text(
                  'FOLLOW',
                          style: TextStyle(
                    color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildAlbumsGrid(List<Map<String, dynamic>> albums) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) => _buildDesktopAlbumCard(albums[index]),
    );
  }

  Widget _buildDesktopAlbumCard(Map<String, dynamic> album) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _navigateToAlbum(album),
        child: Container(
                  decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album Cover
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: FutureBuilder<String>(
                    future: _backblazeService.getImageUrl(
                      album['image_url'],
                      album['file_identifier'],
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          color: Colors.grey[850],
                          child: const Icon(Icons.album, size: 60, color: Colors.white),
                        );
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return Container(
                          color: Colors.grey[850],
                          child: const Icon(Icons.album, size: 60, color: Colors.white),
                        );
                      }
                      return Image.network(
                        snapshot.data!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[850],
                          child: const Icon(Icons.album, size: 60, color: Colors.white),
                        ),
                      );
                    },
                  ),
                ),
              ),
              
              // Album Info
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album['title'] ?? 'Unknown Album',
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
                      album['artist'] ?? 'Unknown Artist',
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
    );
  }

  Widget _buildQuickActionsSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vertical divider
        Container(
          width: 1,
          height: 200, // Adjust height as needed
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.green.withOpacity(0.3),
                Colors.green.withOpacity(0.6),
                Colors.green.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        
        // Quick Actions content
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Column(
                  children: [
                    _buildQuickActionItem(
                      icon: Icons.history,
                      label: 'Recently Played',
                      onTap: () => _showRecentlyPlayed(),
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionItem(
                      icon: Icons.favorite,
                      label: 'Liked Songs',
                      onTap: () => _showLikedSongs(),
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionItem(
                      icon: Icons.playlist_play,
                      label: 'Your Playlists',
                      onTap: () => _showUserPlaylists(),
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionItem(
                      icon: Icons.trending_up,
                      label: 'Top Charts',
                      onTap: () => _showTopCharts(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: Colors.green,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecentlyPlayed() {
    if (recentlyPlayed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No recently played items'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _buildQuickActionDialog(
        title: 'Recently Played',
        icon: Icons.history,
        items: recentlyPlayed.map((album) => {
          'title': album['title'] ?? 'Unknown Album',
          'subtitle': album['artist'] ?? 'Unknown Artist',
          'image_url': album['image_url'],
          'file_identifier': album['file_identifier'],
          'type': 'album',
          'data': album,
        }).toList(),
        onItemTap: (item) {
          Navigator.pop(context);
          _navigateToAlbum(item['data']);
        },
      ),
    );
  }

  void _showLikedSongs() async {
    final user = widget.supabaseClient.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to view liked songs'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      // Fetch liked songs from the database
      final response = await widget.supabaseClient
          .from('user_likes')
          .select('''
            song_id,
            songs_2 (
              id,
              title,
              artist,
              album,
              duration,
              image_url,
              file_identifier,
              audio_url
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(20);

      final likedSongs = response.map((like) => like['songs_2']).toList();

      if (likedSongs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No liked songs found'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => _buildQuickActionDialog(
          title: 'Liked Songs',
          icon: Icons.favorite,
          items: likedSongs.map((song) => {
            'title': song['title'] ?? 'Unknown Song',
            'subtitle': song['artist'] ?? 'Unknown Artist',
            'image_url': song['image_url'],
            'file_identifier': song['file_identifier'],
            'type': 'song',
            'data': song,
          }).toList(),
          onItemTap: (item) {
            Navigator.pop(context);
            _playSearchResult(item['data']);
          },
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading liked songs: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showUserPlaylists() async {
    final user = widget.supabaseClient.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to view your playlists'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final response = await widget.supabaseClient
          .from('playlist')  // Changed to 'playlist' to match DB schema
          .select('id, playlist_name, description, image_url, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final userPlaylists = List<Map<String, dynamic>>.from(response);

      if (userPlaylists.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No playlists found. Create your first playlist!'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => _buildQuickActionDialog(
          title: 'Your Playlists',
          icon: Icons.playlist_play,
          items: userPlaylists.map((playlist) => {
            'title': playlist['playlist_name'] ?? 'Unnamed Playlist',
            'subtitle': playlist['description'] ?? 'No description',
            'image_url': playlist['image_url'],
            'type': 'playlist',
            'data': playlist,
          }).toList(),
          onItemTap: (item) {
            Navigator.pop(context);
            _navigateToPlaylist(item['data']);
          },
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading playlists: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showTopCharts() {
    if (topCharts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No top charts available'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _buildQuickActionDialog(
        title: 'Top Charts',
        icon: Icons.trending_up,
        items: topCharts.asMap().entries.map((entry) {
          final index = entry.key;
          final album = entry.value;
          return {
            'title': '${index + 1}. ${album['title'] ?? 'Unknown Album'}',
            'subtitle': album['artist'] ?? 'Unknown Artist',
            'image_url': album['image_url'],
            'file_identifier': album['file_identifier'],
            'type': 'album',
            'data': album,
          };
        }).toList(),
        onItemTap: (item) {
          Navigator.pop(context);
          _navigateToAlbum(item['data']);
        },
      ),
    );
  }

  Widget _buildQuickActionDialog({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required Function(Map<String, dynamic>) onItemTap,
  }) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(icon, color: Colors.green, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Items List
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
                      onTap: () => onItemTap(item),
          child: Container(
                        padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                            // Image
                ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: FutureBuilder<String>(
                                future: _backblazeService.getImageUrl(
                                  item['image_url'],
                                  item['file_identifier'],
                                ),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return Container(
                                      width: 48,
                                      height: 48,
                          color: Colors.grey[850],
                                      child: Icon(
                                        item['type'] == 'song' ? Icons.music_note : Icons.album,
                                        size: 24,
                                        color: Colors.white,
                                      ),
                                    );
                                  }
                                  if (snapshot.hasError || !snapshot.hasData) {
                                    return Container(
                                      width: 48,
                                      height: 48,
                                      color: Colors.grey[850],
                                      child: Icon(
                                        item['type'] == 'song' ? Icons.music_note : Icons.album,
                                        size: 24,
                                        color: Colors.white,
                                      ),
                                    );
                                  }
                                  return Image.network(
                                    snapshot.data!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 48,
                                      height: 48,
                                      color: Colors.grey[850],
                                      child: Icon(
                                        item['type'] == 'song' ? Icons.music_note : Icons.album,
                                        size: 24,
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                                    item['title'],
                        style: const TextStyle(
                          color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                      ),
                                  const SizedBox(height: 4),
                      Text(
                                    item['subtitle'],
                        style: TextStyle(
                          color: Colors.grey[400],
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            
                            // Action Icon
                            Icon(
                              item['type'] == 'song' ? Icons.play_arrow : Icons.arrow_forward_ios,
                              color: Colors.grey[400],
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSongsTab() {
    final songs = categorizedResults['Songs'] ?? [];

    if (songs.isEmpty) {
      return _buildEmptySearchState();
    }

    // Calculate bottom padding based on whether music player is visible
    final bottomPadding = widget.currentlyPlayingSong != null ? 120.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(32.0, 24.0, 32.0, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Songs', Icons.music_note),
          const SizedBox(height: 16),
          _buildSongsList(songs),
        ],
      ),
    );
  }

  Widget _buildArtistsTab() {
    final artists = categorizedResults['Artists'] ?? [];

    if (artists.isEmpty) {
      return _buildEmptySearchState();
    }

    // Calculate bottom padding based on whether music player is visible
    final bottomPadding = widget.currentlyPlayingSong != null ? 120.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(32.0, 24.0, 32.0, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Artists', Icons.person),
          const SizedBox(height: 16),
          _buildArtistsGrid(artists),
        ],
      ),
    );
  }

  Widget _buildAlbumsTab() {
    final albums = categorizedResults['Albums'] ?? [];

    if (albums.isEmpty) {
      return _buildEmptySearchState();
    }

    // Calculate bottom padding based on whether music player is visible
    final bottomPadding = widget.currentlyPlayingSong != null ? 120.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(32.0, 24.0, 32.0, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Albums', Icons.album),
          const SizedBox(height: 16),
          _buildAlbumsGrid(albums),
        ],
      ),
    );
  }

  Widget _buildPlaylistsTab() {
    return const Center(
      child: Text('Playlists feature coming soon', style: TextStyle(color: Colors.white)),
    );
  }

  Widget _buildBrowseArtistCircle(Map<String, dynamic> artist) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _navigateToArtist(artist),
        child: Column(
          children: [
            // Artist Image
            Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundImage: artist['image_url'] != null ? NetworkImage(artist['image_url']) : null,
                  backgroundColor: Colors.grey[850],
                  child: artist['image_url'] == null ? const Icon(Icons.person, size: 60, color: Colors.white) : null,
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(60),
                      onTap: () => _navigateToArtist(artist),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Artist Name
            SizedBox(
              width: 100,
              child: Text(
                artist['name'] ?? 'Unknown Artist',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSongContextMenu(Map<String, dynamic> song) async {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset position = box.localToGlobal(Offset.zero);
    
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx + 40,
        position.dy + 40,
        position.dx + 41,
        position.dy + 41,
      ),
      items: [
        const PopupMenuItem<String>(value: 'play', child: Text('Play Now')),
        const PopupMenuItem<String>(value: 'add_to_queue', child: Text('Add to Queue')),
        const PopupMenuItem<String>(value: 'add_to_playlist', child: Text('Add to Playlist')),
        const PopupMenuItem<String>(value: 'view_album', child: Text('View Album')),
        const PopupMenuItem<String>(value: 'view_artist', child: Text('View Artist')),
      ],
    );
    
    if (selected == 'play') {
      _playSearchResult(song);
    } else if (selected == 'add_to_queue') {
      _addToQueue(song);
    } else if (selected == 'add_to_playlist') {
      _showAddToPlaylistDialog(song);
    } else if (selected == 'view_album') {
      _navigateToAlbum({'id': song['album_id'], 'title': song['album'] ?? 'Album'});
    } else if (selected == 'view_artist') {
      _navigateToArtist({'id': song['artist_id'], 'name': song['artist'] ?? 'Artist'});
    }
  }

  void _addToQueue(Map<String, dynamic> song) {
    // Add the song after the current song in the queue
    if (widget.currentlyPlayingSong == null) {
      // No song is currently playing, just play this song
      _playSearchResult(song);
      return;
    }
    final currentQueue = List<Map<String, dynamic>>.from(widget.currentlyPlayingSong!['queue'] ?? []);
    final currentSongId = widget.currentlyPlayingSong!['id'];
    final currentIndex = currentQueue.indexWhere((s) => s['id'] == currentSongId);
    if (currentIndex == -1) {
      // Fallback: append to end
      currentQueue.add(song);
    } else {
      currentQueue.insert(currentIndex + 1, song);
    }
    // Update the queue and keep the current song playing
    final updatedSong = {
      ...widget.currentlyPlayingSong!,
      'queue': currentQueue,
    };
    widget.onSongSelected(updatedSong);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to queue')),
    );
  }

  void _showAddToPlaylistDialog(Map<String, dynamic> song) async {
    final supabase = widget.supabaseClient;
    final user = supabase.auth.currentUser;
    
    // Store the context that has access to Scaffold
    final scaffoldContext = context;
    
    if (user == null) {
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        const SnackBar(content: Text('Please sign in to add to playlist.')),
      );
      return;
    }

    // Fetch playlists for the user
    List<Map<String, dynamic>> playlists = [];
    try {
      final data = await supabase
          .from('playlist')  // Changed to 'playlist' to match DB schema
          .select('id, playlist_name, image_url, user_id, description, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      playlists = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(content: Text('Error loading playlists: $e')),
      );
      return;
    }

    String? selectedPlaylistId;
    final TextEditingController newPlaylistController = TextEditingController();
    bool creatingNew = false;
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF23272A),
              title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!creatingNew) ...[
                      if (playlists.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('No playlists found. Create a new one!', style: TextStyle(color: Colors.white70)),
                        ),
                      if (playlists.isNotEmpty)
                        ...playlists.map((playlist) => RadioListTile<String>(
                              value: playlist['id'].toString(),
                              groupValue: selectedPlaylistId,
                              onChanged: (val) => setState(() => selectedPlaylistId = val),
                              title: Text(playlist['playlist_name'] ?? 'Unnamed Playlist', style: const TextStyle(color: Colors.white)),
                              subtitle: playlist['description'] != null && playlist['description'].toString().isNotEmpty
                                  ? Text(playlist['description'], style: const TextStyle(color: Colors.white54, fontSize: 12))
                                  : null,
                              secondary: playlist['image_url'] != null
                                  ? CircleAvatar(backgroundImage: NetworkImage(playlist['image_url']), radius: 18)
                                  : const CircleAvatar(child: Icon(Icons.music_note)),
                              activeColor: Colors.green,
                            )),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () => setState(() => creatingNew = true),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                    if (creatingNew) ...[
                      TextField(
                        controller: newPlaylistController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Playlist name',
                          hintStyle: TextStyle(color: Colors.white54),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    if (newPlaylistController.text.trim().isEmpty) return;
                                    setState(() => isLoading = true);
                                    try {
                                      final response = await supabase.from('playlist').insert({
                                        'playlist_name': newPlaylistController.text.trim(),
                                        'user_id': user.id,
                                        'created_at': DateTime.now().toIso8601String(),
                                        'type': 'user_created', // Add the required type field
                                      }).select().single();
                                      playlists.insert(0, response);
                                      selectedPlaylistId = response['id'].toString();
                                      creatingNew = false;
                                      newPlaylistController.clear();
                                    } catch (e) {
                                      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                                        SnackBar(content: Text('Error creating playlist: $e')),
                                      );
                                    } finally {
                                      setState(() => isLoading = false);
                                    }
                                  },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            child: isLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Create'),
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: isLoading ? null : () => setState(() => creatingNew = false),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  onPressed: (selectedPlaylistId != null && !creatingNew && !isLoading)
                      ? () async {
                          setState(() => isLoading = true);
                          try {
                            // Insert song into playlist_songs table
                            await supabase.from('playlist_songs').insert({
                              'playlist_id': selectedPlaylistId,
                              'song_id': song['id'],
                              'added_at': DateTime.now().toIso8601String(),
                            });
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                              const SnackBar(content: Text('Song added to playlist!')),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                              SnackBar(content: Text('Error adding to playlist: $e')),
                            );
                          } finally {
                            setState(() => isLoading = false);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
