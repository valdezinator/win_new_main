import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart';
import 'music_player.dart';
import 'widgets/queue_list.dart';
import 'dart:math';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    _loadAlbums();
    // Initialize current playing index if a song is playing
    if (widget.currentlyPlayingSong != null) {
      _updateCurrentPlayingIndex();
    }
  }

  @override
  void dispose() {
    // Remove _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAlbums() async {
    try {
      final response = await widget.supabaseClient
          .from('albums')
          .select()
          .order('created_at');

      setState(() {
        albums = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      //print('Error loading albums: $e');
      setState(() {
        isLoading = false;
      });
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

  Future<void> searchSongs(String query) async {
    if (query.isEmpty) {
      setState(() {
        categorizedResults = {};
        isSearching = false;
      });
      return;
    }

    setState(() => isSearching = true);

    try {
      final songsFuture = widget.supabaseClient
          .from('songs')
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
    } catch (e) {
      //print('Error searching content: $e');
      setState(() => isSearching = false);
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

  void _playSearchResult(Map<String, dynamic> song) {
    if (song['audio_url'] != null) {
      // Add search context to the song
      final songWithSearchContext = {
        ...Map<String, dynamic>.from(song),
        'queue': categorizedResults['Songs'] ?? [],  // Use search results as queue
        'isPlaying': true,
      };
      widget.onSongSelected(songWithSearchContext);
    } else {
      //print('Error: No audio URL for song ${song['title']}');
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
          color: isHovered ? Colors.white.withOpacity(0.1) : Colors.transparent,
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
                  child: Image.network(
                    song['image_url'] ?? '',
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
          title: Text(
            song['title'] ?? 'Unknown',
            style: TextStyle(
              color: isCurrentlyPlaying ? Colors.green : Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: compact ? 14 : 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song['artist'] ?? 'Unknown Artist',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: compact ? 12 : 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
              // color: Colors.black.withOpacity(0.3),
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: GoogleFonts.montserrat(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'What do you want to listen to?',
                          hintStyle: GoogleFonts.montserrat(
                          color: Colors.grey[400],
                          // No direct margin property, so use a Container as prefix
                          ),
                          prefixIcon: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: SvgPicture.asset(
                            'assets/icons/browse_icon.svg',
                            width: 24,
                            height: 24,
                          ),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.fromLTRB(16, 15, 16, 12), // Increased top padding for hint text
                        ),
                        onChanged: (value) => searchSongs(value),
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
              child: _searchController.text.isEmpty
                ? _buildBrowseContent()
                : isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _buildSearchResults(),
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
    // This would be the content shown when no search is active
    return const Center(
      child: Text(
        'Browse content will appear here',
        style: TextStyle(color: Colors.white, fontSize: 16),
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
              height: 130,
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
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, idx) => _buildSearchAlbumCard(categorizedResults['Albums']![idx]),
              ),
            ),
            const SizedBox(height: 32),
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
