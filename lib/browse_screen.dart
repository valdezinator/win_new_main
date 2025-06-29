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
      final audioUrl = await _backblazeService.getAudioUrl(
        song['audio_url'],
        song['file_identifier'],
      );
      print('Resolved audio URL (BrowseScreen): $audioUrl');
      final songWithSearchContext = {
        ...Map<String, dynamic>.from(song),
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
                  onPressed: () {},
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Section
          _buildWelcomeSection(),
          const SizedBox(height: 32),

          // Featured Albums
          if (featuredAlbums.isNotEmpty) ...[
            _buildSectionHeader('Featured Albums'),
            const SizedBox(height: 16),
            _buildAlbumGrid(featuredAlbums),
            const SizedBox(height: 32),
          ],

          // Recently Played
          if (recentlyPlayed.isNotEmpty) ...[
            _buildSectionHeader('Recently Played'),
            const SizedBox(height: 16),
            _buildAlbumGrid(recentlyPlayed),
            const SizedBox(height: 32),
          ],

          // Top Charts
          if (topCharts.isNotEmpty) ...[
            _buildSectionHeader('Top Charts'),
            const SizedBox(height: 16),
            _buildTopChartsSection(),
            const SizedBox(height: 32),
          ],

          // New Releases
          if (newReleases.isNotEmpty) ...[
            _buildSectionHeader('New Releases'),
            const SizedBox(height: 16),
            _buildAlbumGrid(newReleases),
            const SizedBox(height: 32),
          ],

          // Trending Artists
          if (trendingArtists.isNotEmpty) ...[
            _buildSectionHeader('Trending Artists'),
            const SizedBox(height: 16),
            _buildArtistGrid(trendingArtists),
            const SizedBox(height: 32),
          ],

          // Popular Playlists
          if (popularPlaylists.isNotEmpty) ...[
            _buildSectionHeader('Popular Playlists'),
            const SizedBox(height: 16),
            _buildPlaylistGrid(popularPlaylists),
            const SizedBox(height: 32),
          ],

          // Browse by Genre
          if (genres.isNotEmpty) ...[
            _buildSectionHeader('Browse by Genre'),
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
                  _buildSectionHeader('${genre['name']} Music'),
                  const SizedBox(height: 16),
                  _buildAlbumGrid(genreAlbumsList),
                  const SizedBox(height: 32),
                ],
              );
            }
            return const SizedBox.shrink();
          }),

          const SizedBox(height: 100), // Space for player
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildAlbumGrid(List<Map<String, dynamic>> albums) {
    return SizedBox(
      height: 200,
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
                            height: 160,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 60, color: Colors.white),
                          );
                        }
                        if (snapshot.hasError || !snapshot.hasData) {
                          return Container(
                            width: 160,
                            height: 160,
                            color: Colors.grey[850],
                            child: const Icon(Icons.album, size: 60, color: Colors.white),
                          );
                        }
                        return Image.network(
                          snapshot.data!,
                          width: 160,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 160,
                            height: 160,
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
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: artists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 24),
        itemBuilder: (context, index) => _buildBrowseArtistCircle(artists[index]),
      ),
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

  Widget _buildPlaylistGrid(List<Map<String, dynamic>> playlists) {
    return SizedBox(
      height: 200,
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
    // Navigate to album view
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening album: ${album['title']}')),
    );
  }

  void _navigateToArtist(Map<String, dynamic> artist) {
    // Navigate to artist view
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening artist: ${artist['name']}')),
    );
  }

  void _navigateToPlaylist(Map<String, dynamic> playlist) {
    // Navigate to playlist view
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening playlist: ${playlist['title']}')),
    );
  }

  void _navigateToGenre(Map<String, dynamic> genre) {
    // Navigate to genre view
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening genre: ${genre['name']}')),
    );
  }

  Widget _buildShimmerLoader() {
    // Simple shimmer/skeleton loader for search results
    return ListView.builder(
      padding: const EdgeInsets.all(24.0),
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
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Text(
            'No results found',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      );
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

  Widget _buildAllResultsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Result and Songs Side by Side
          if ((categorizedResults['Songs']?.isNotEmpty ?? false) ||
              (categorizedResults['Albums']?.isNotEmpty ?? false) ||
              (categorizedResults['Artists']?.isNotEmpty ?? false)) ...[
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Top Result',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Songs',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Result - Half Width
                Expanded(
                  flex: 1,
                  child: _buildTopResultCard(),
                ),
                const SizedBox(width: 24),
                // 3 Songs - Half Width
                if (categorizedResults['Songs']?.isNotEmpty ?? false)
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        // Take up to 3 songs
                        ...List.generate(
                          min(3, categorizedResults['Songs']!.length),
                          (index) => _buildSearchResult(
                            categorizedResults['Songs']![index],
                            categorizedResults['Songs']![index]['isPlaying'] == true,
                            index: index,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
          ],

          // Artists Section
          if (categorizedResults['Artists']?.isNotEmpty ?? false) ...[
            const Text(
              'Artists',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180, // Fixed height for horizontal list
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categorizedResults['Artists']!.length,
                separatorBuilder: (_, __) => const SizedBox(width: 24),
                itemBuilder: (context, idx) => _buildSearchArtistCircle(categorizedResults['Artists']![idx]),
              ),
            ),
            const SizedBox(height: 32),
          ],

          // Albums Section
          if (categorizedResults['Albums']?.isNotEmpty ?? false) ...[
            const Text(
              'Albums',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categorizedResults['Albums']!.length,
                separatorBuilder: (_, __) => const SizedBox(width: 24),
                itemBuilder: (context, idx) => _buildSearchAlbumCard(categorizedResults['Albums']![idx]),
              ),
            ),
          ],

          // Remaining Songs Section
          if ((categorizedResults['Songs']?.length ?? 0) > 3) ...[
            const Text(
              'More Songs',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...categorizedResults['Songs']!.asMap().entries.where((entry) => entry.key >= 3).map((entry) =>
              _buildSearchResult(
                entry.value,
                entry.value['isPlaying'] == true,
                index: entry.key,
              )
            ),
          ],

          const SizedBox(height: 100), // Space for player
        ],
      ),
    );
  }

  Widget _buildSongsTab() {
    final songs = categorizedResults['Songs'] ?? [];

    if (songs.isEmpty) {
      return const Center(
        child: Text('No songs found', style: TextStyle(color: Colors.white)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24.0),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        return _buildSearchResult(
          songs[index],
          songs[index]['isPlaying'] == true,
          index: index,
        );
      },
    );
  }

  Widget _buildArtistsTab() {
    final artists = categorizedResults['Artists'] ?? [];

    if (artists.isEmpty) {
      return const Center(
        child: Text('No artists found', style: TextStyle(color: Colors.white)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        return _buildSearchArtistCircle(artists[index]);
      },
    );
  }

  Widget _buildAlbumsTab() {
    final albums = categorizedResults['Albums'] ?? [];

    if (albums.isEmpty) {
      return const Center(
        child: Text('No albums found', style: TextStyle(color: Colors.white)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 24,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        return _buildSearchAlbumCard(albums[index]);
      },
    );
  }

  Widget _buildPlaylistsTab() {
    return const Center(
      child: Text('Playlists feature coming soon', style: TextStyle(color: Colors.white)),
    );
  }

  // --- Top Result Card ---
  Widget _buildTopResultCard() {
    // Prefer song > artist > album for top result
    final song = (categorizedResults['Songs']?.isNotEmpty ?? false) ? categorizedResults['Songs']![0] : null;
    final artist = (categorizedResults['Artists']?.isNotEmpty ?? false) ? categorizedResults['Artists']![0] : null;
    final album = (categorizedResults['Albums']?.isNotEmpty ?? false) ? categorizedResults['Albums']![0] : null;

    if (song != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _playSearchResult(song),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Song Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song['image_url'] != null
                      ? Image.network(song['image_url'], width: 100, height: 100, fit: BoxFit.cover)
                      : Container(
                          width: 100,
                          height: 100,
                          color: Colors.grey[850],
                          child: const Icon(Icons.music_note, size: 50, color: Colors.white),
                        ),
                ),
                const SizedBox(width: 24),
                // Song Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                // Play Button
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
                    onPressed: () => _playSearchResult(song),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (artist != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // Navigate to artist view
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Artist Image
                CircleAvatar(
                  radius: 50,
                  backgroundImage: artist['image_url'] != null ? NetworkImage(artist['image_url']) : null,
                  backgroundColor: Colors.grey[850],
                  child: artist['image_url'] == null ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                ),
                const SizedBox(width: 24),
                // Artist Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                // Follow Button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'FOLLOW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (album != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // Navigate to album view
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Album Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: album['image_url'] != null
                      ? Image.network(album['image_url'], width: 100, height: 100, fit: BoxFit.cover)
                      : Container(
                          width: 100,
                          height: 100,
                          color: Colors.grey[850],
                          child: const Icon(Icons.album, size: 50, color: Colors.white),
                        ),
                ),
                const SizedBox(width: 24),
                // Album Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                // Play Button
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
                    onPressed: () {
                      // Play album
                    },
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
