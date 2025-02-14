import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_page.dart';
import 'music_player.dart';  // Add this import
import 'widgets/queue_list.dart';

class BrowseScreen extends StatefulWidget {
  final SupabaseClient supabaseClient;
  final Function(Map<String, dynamic>) onSongSelected;
  final Map<String, dynamic>? currentlyPlayingSong;

  const BrowseScreen({
    Key? key, 
    required this.supabaseClient,
    required this.onSongSelected,
    this.currentlyPlayingSong,
  }) : super(key: key);

  @override
  _BrowseScreenState createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _searchController = TextEditingController();
  Map<String, List<Map<String, dynamic>>> categorizedResults = {};
  bool isSearching = false;
  List<Map<String, dynamic>> albums = [];
  bool isLoading = true;
  int? currentPlayingIndex;
  bool showQueue = false;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
    // Initialize current playing index if a song is playing
    if (widget.currentlyPlayingSong != null) {
      _updateCurrentPlayingIndex();
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
        isLoading = false;
      });
    } catch (e) {
      print('Error loading albums: $e');
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
      print('Error searching content: $e');
      setState(() => isSearching = false);
    }
  }

  Widget _buildSearchAlbumTile(Map<String, dynamic> album) {
    return ListTile(
      leading: album['image_url'] != null 
          ? Image.network(album['image_url'], width: 50, height: 50, fit: BoxFit.cover)
          : const Icon(Icons.album, size: 50),
      title: Text(album['title'] ?? 'Unknown Album', style: const TextStyle(color: Colors.white)),
      subtitle: Text(album['artist'] ?? 'Unknown Artist', style: TextStyle(color: Colors.grey[400])),
      onTap: () {
        // Handle album tap if needed
      },
    );
  }

  Widget _buildSearchArtistTile(Map<String, dynamic> artist) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: artist['image_url'] != null 
            ? NetworkImage(artist['image_url'])
            : null,
        child: artist['image_url'] == null ? const Icon(Icons.person) : null,
      ),
      title: Text(artist['name'] ?? 'Unknown Artist', style: const TextStyle(color: Colors.white)),
      onTap: () {
        // Handle artist tap if needed
      },
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
      print('Error: No audio URL for song ${song['title']}');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Widget _buildSearchResult(Map<String, dynamic> song, bool isCurrentlyPlaying) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          tileColor: Colors.white.withOpacity(0.05),
          leading: Container(
            width: 48,
            height: 48,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    song['image_url'] ?? '',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[850],
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
                  ),
                ),
                if (isCurrentlyPlaying)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.green,
                        size: 24,
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
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song['artist'] ?? 'Unknown Artist',
                style: TextStyle(color: Colors.grey[400]),
              ),
              // Text(
              //   song['album'] ?? 'Unknown Album',
              //   style: TextStyle(color: Colors.grey[600], fontSize: 12),
              // ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.favorite_border,
                  color: Colors.grey[400],
                ),
                onPressed: () {},
              ),
              Text(
                _formatDuration(song['duration']),
                style: TextStyle(color: Colors.grey[400]),
              ),
              const SizedBox(width: 8),
              Icon(Icons.more_vert, color: Colors.grey[400]),
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
    final browseCategories = [
      {
        'title': 'Pop',
        'colors': [Colors.pink[400]!, Colors.pink[700]!],
        'icon': Icons.music_note,
      },
      {
        'title': 'Hip-Hop',
        'colors': [Colors.orange[400]!, Colors.orange[700]!],
        'icon': Icons.mic,
      },
      {
        'title': 'Rock',
        'colors': [Colors.red[400]!, Colors.red[700]!],
        'icon': Icons.electric_bolt,
      },
      {
        'title': 'Focus',
        'colors': [Colors.green[400]!, Colors.green[700]!],
        'icon': Icons.psychology,
      },
      {
        'title': 'Mood',
        'colors': [Colors.purple[400]!, Colors.purple[700]!],
        'icon': Icons.mood,
      },
      {
        'title': 'Workout',
        'colors': [Colors.blue[400]!, Colors.blue[700]!],
        'icon': Icons.fitness_center,
      },
      // Add more categories as needed
    ];

    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'What do you want to listen to?',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (value) => searchSongs(value),
                  ),
                ),
              ),

              // Browse Categories
              if (_searchController.text.isEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    'Browse all',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, // Increased from 2 for more columns
                      childAspectRatio: 1,
                      crossAxisSpacing: 12, // Reduced spacing
                      mainAxisSpacing: 12,  // Reduced spacing
                    ),
                    itemCount: browseCategories.length,
                    itemBuilder: (context, index) {
                      final category = browseCategories[index];
                      return _buildBrowseCard(
                        category['title'] as String,
                        category['colors'] as List<Color>,
                        category['icon'] as IconData,
                      );
                    },
                  ),
                ),
              ],

              // Categorised Search Results
              if (_searchController.text.isNotEmpty)
                isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : categorizedResults.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: categorizedResults.entries.map((entry) {
                          final category = entry.key;
                          final items = entry.value;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  if (category == 'Songs') {
                                    return _buildSearchResult(item, item['isPlaying']);
                                  } else if (category == 'Albums') {
                                    return _buildSearchAlbumTile(item);
                                  } else if (category == 'Artists') {
                                    return _buildSearchArtistTile(item);
                                  }
                                  return Container();
                                },
                              ),
                            ],
                          );
                        }).toList(),
                      )
                    : const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text('No results found', style: TextStyle(color: Colors.white)),
                      ),
              const SizedBox(height: 100), // Space for player
            ],
          ),
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
}
