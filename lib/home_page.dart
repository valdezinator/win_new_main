import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase/supabase.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'browse_screen.dart';
import 'album_view.dart';
import 'music_player.dart';
import 'services/audio_service.dart';
import 'services/jam_session_service.dart';
import 'widgets/queue_list.dart';
import 'library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http; // NEW import
import 'dart:convert'; // NEW import
import 'package:flutter_svg/flutter_svg.dart'; // Add this import
import 'package:cached_network_image/cached_network_image.dart'; // NEW import for caching images
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic>? initialSong;
  final bool autoplay;

  const HomeScreen({
    Key? key,
    this.initialSong,
    this.autoplay = false,
  }) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final SupabaseClient supabaseClient = SupabaseClient(
    'https://yaysfbsmvtyqpbfhxstj.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlheXNmYnNtdnR5cXBiZmh4c3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzI0NDQ3NDgsImV4cCI6MjA0ODAyMDc0OH0.7d_RsoyQ5RN6Whj6flbd5W0CSLiUpJ6HfRFVEnQKsf8'
  );
  late TabController _tabController;
  Map<String, dynamic>? _currentSong;
  bool showQueue = false;
  final AudioService _audioService = AudioService();

  // Add user name - this would normally come from your auth service
  final String userName = "Peter";
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});  // Rebuild to update box colors
      }
    });
    _setupAudioListener();
    _initializeLastPlayedSong();
    _initializeJamSessionService();
  }
  
  // Initialize JamSessionService with the current user ID
  void _initializeJamSessionService() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await JamSessionService().initialize(userId);
    }
  }

  void _setupAudioListener() {
    _audioService.currentSongStream.listen((song) {
      setState(() => _currentSong = song);
    });
  }

  void _initializeLastPlayedSong() async {
    if (widget.initialSong != null) {
      setState(() => _currentSong = widget.initialSong);
      // Removed auto-play code
    }
  }

  @override
  void dispose() async {
    // Save current song state before disposing
    if (_currentSong != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_played_song', json.encode(_currentSong));
      await prefs.setBool('was_playing', _audioService.isPlaying);
    }
    _tabController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> fetchSongs() async {
    try {
      final response = await supabaseClient
          .from('songs')
          .select()
          .order('created_at');

      if (response.isEmpty) {
        throw Exception('No data received from Supabase');
      }

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('Error fetching songs: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchHitAlbums() async {
    try {
      final response = await supabaseClient
          .from('albums')
          .select('*, id')
          .eq('category', 'album, hits')
          .order('release_date', ascending: false);

      // print('Hit Albums Response: $response');

      if (response.isEmpty) {
        throw Exception('No hit albums found');
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // print('Error fetching hit albums: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchRecentlyPlayed() async {
    try {
      final response = await supabaseClient
          .from('user_play_history')
          .select('*, songs(*)')
          .order('played_at', ascending: false)
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching recently played: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchTrendingNow() async {
    try {
      final response = await supabaseClient
          .from('songs')
          .select()
          .order('play_count', ascending: false)
          .limit(10);
      final trendingList = List<Map<String, dynamic>>.from(response);
      if (trendingList.isEmpty) {  // Fallback using Jamendo API
        const jamendoUrl =
            "https://api.jamendo.com/v3.0/tracks/?client_id=Ydc71431e&order=popularity_total&limit=10";
        final jamendoResponse = await http.get(Uri.parse(jamendoUrl));
        if (jamendoResponse.statusCode == 200) {
          final data = jsonDecode(jamendoResponse.body);
          final tracks = data['results'] as List;
          return tracks.map((track) {
            return {
              'title': track['name'],
              'audio_url': track['audio'], // sample audio url from Jamendo
              'image_url': track['image'],
            };
          }).toList();
        } else {
          print('Jamendo API error: ${jamendoResponse.statusCode}');
        }
      }
      return trendingList;
    } catch (e) {
      print('Error fetching trending songs: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchGenres() async {
    try {
      final response = await supabaseClient
          .from('genres')
          .select()
          .limit(8);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching genres: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchArtists() async {
    try {
      final response = await supabaseClient
          .from('artists')
          .select('name, image_url')
          .limit(10);  // Limiting to 10 artists for the scrolling view

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching artists: $e');
      return [];
    }
  }

  // NEW: fetch new releases from a "new_releases" table or API
  Future<List<Map<String, dynamic>>> fetchNewReleases() async {
    try {
      final response = await supabaseClient
          .from('new_releases')
          .select()
          .order('release_date', ascending: false);
      if (response.isEmpty) {
        throw Exception('No new releases found');
      }
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching new releases: $e');
      return [];
    }
  }

  Widget _buildAlbumCard(Map<String, dynamic> album) {
    return StatefulBuilder(
      builder: (context, setState) {
        return MouseRegion(
          onEnter: (_) => setState(() {}),
          onExit: (_) => setState(() {}),
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AlbumView(
                    album: {
                      ...album,
                      'id': album['id'], // Ensure ID is passed
                      'title': album['title'] ?? 'Unknown Album',
                      'artist': album['artist'] ?? 'Unknown Artist',
                      'image_url': album['image_url'],
                      'category': album['category'] ?? 'album'
                    },
                    supabaseClient: supabaseClient,
                    onSongSelected: (song) {
                      setState(() => _currentSong = song);
                      _audioService.playSong(song);
                    },
                    currentlyPlayingSong: _currentSong,
                  ),
                ),
              );
            },
            child: Container(
              width: 200,
              margin: const EdgeInsets.only(right: 16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withOpacity(0.05),
                ),
                child: SingleChildScrollView( // Wrap in SingleChildScrollView
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, // Add this
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: album['image_url'] != null
                          ? CachedNetworkImage(
                              imageUrl: album['image_url'],
                              height: 200,
                              width: 200,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                Container(
                                  height: 200,
                                  width: 200,
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.album, color: Colors.white, size: 50),
                                ),
                            )
                          : Container(
                              height: 200,
                              width: 200,
                              color: Colors.grey[800],
                              child: const Icon(Icons.album, color: Colors.white, size: 50),
                            ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album['title'] ?? 'No Title',
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
                              album['artist'] ?? 'Unknown Artist',
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    );
  }

  // NEW: Helper to build a trending card (similar to quick play)
  Widget _buildTrendingCard(Map<String, dynamic> song) {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      child: InkWell(
        onTap: () => playSong(song),
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                  child: CachedNetworkImage(
                    imageUrl: song['image_url'] ?? '',
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[850],
                      child: const Icon(Icons.music_note, color: Colors.white54, size: 16),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    song['title'] ?? 'Unknown',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void playSong(Map<String, dynamic> song) {
    try {
      print('Playing song: ${song.toString()}');
      // Ensure we have all required fields
      if (song['audio_url'] == null) {
        print('Error: No audio URL provided');
        return;
      }

      // Create complete song context with queue
      final songWithContext = {
        ...Map<String, dynamic>.from(song),
        'queue': [], // Initialize empty queue if none exists
        'image_url': song['image_url'] ?? '', // Ensure image_url exists
        'artist': song['artist'] ?? 'Unknown Artist',
        'title': song['title'] ?? 'Unknown Title',
      };

      // Update UI state
      setState(() {
        _currentSong = songWithContext;
      });

      // Play the song
      _audioService.playSong(songWithContext);
    } catch (e) {
      print('Error playing song: $e');
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing song: ${e.toString()}')),
      );
    }
  }

  void _toggleQueue(bool show) {
    setState(() {
      showQueue = show;
    });
  }

  // Add this method to _HomeScreenState
  void _testPlaySong() {
    final testSong = {
      'id': 'test',
      'title': 'Test Song',
      'artist': 'Test Artist',
      'audio_url': 'YOUR_TEST_AUDIO_URL_HERE', // Put a working audio URL here
      'image_url': 'https://picsum.photos/200',
    };
    playSong(testSong);
  }

  Future<void> _handleSignOut() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear auth token
    await prefs.remove('access_token');
    // Clear last played song state
    await prefs.remove('last_played_song');
    await prefs.remove('was_playing');
    // Sign out from Supabase
    await Supabase.instance.client.auth.signOut();

    // Navigate back to sign in screen
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const SignInScreen()),
    );
  }

  Widget _buildNavItem(int index, String svgPath, String text) {
    final isSelected = _tabController.index == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _tabController.animateTo(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                svgPath,
                width: 20,
                height: 20,
                color: isSelected ? Colors.white : Colors.grey,
              ),
              const SizedBox(width: 12),
              Text(
                text,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      body: Stack(
        children: [
          // Main content row
          Row(
            children: [
              // Navigation Sidebar Container
              SizedBox(
                width: 232, // 200 + 16 * 2 for margins
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 108), // Added bottom padding of 108px to account for music player height
                  child: Material(
                    elevation: 8,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1), // Change from 0.1 to 0.05 for 5% opacity
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
                          _buildNavItem(0, 'assets/icons/home_icon.svg', 'Home'),
                          _buildNavItem(1, 'assets/icons/search_icon.svg', 'Search'),
                          _buildNavItem(2, 'assets/icons/library_icon.svg', 'Library'),
                          _buildNavItem(3, 'assets/icons/profile_icon.svg', 'Profile'),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Container(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _handleSignOut,  // Add sign out handler
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Main content area
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildHomeContent(),
                    BrowseScreen(
                      supabaseClient: supabaseClient,
                      onSongSelected: playSong,
                      currentlyPlayingSong: _currentSong,
                    ),
                    LibraryScreen(
                      supabaseClient: supabaseClient,
                      currentlyPlayingSong: _currentSong,
                    ),
                    ProfileScreen(supabaseClient: supabaseClient),
                  ],
                ),
              ),
            ],
          ),

          // Music Player
          if (_currentSong != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: MusicPlayer(
                key: ValueKey(_currentSong!['id']),
                song: _currentSong!,
                onQueueToggle: (show) => setState(() => showQueue = show),
                showQueue: showQueue,
              ),
            ),

          // Queue List (conditionally shown)
          if (showQueue && _currentSong != null)
            Positioned(
              top: 60.0, // Added top margin to avoid overlap with a potential top bar
              right: 0,
              bottom: 80.0, // Height of the MusicPlayer, ensures QueueList doesn't overlap it
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
                  _audioService.playSong(songWithQueue);
                },
              ),
            ),
        ],
      ),
      // floatingActionButton: ElevatedButton(
      //   onPressed: _testPlaySong,
      //   child: Text('Test Play'),
      // ),
    );
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24.0, 24.0, 24.0, _currentSong != null ? 124.0 : 24.0), // Adjust bottom padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Add this
          children: [
            // Greeting Section
            Text(
              'Greetings, $userName',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 32),

            // Quick Play Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Quick Play',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to see all quick play songs
                  },
                  child: Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchSongs(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  print('Error in Quick Play: ${snapshot.error}');
                  return const Center(
                    child: Text(
                      'Error loading songs',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      'No songs found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final songs = snapshot.data!;
                // Limit to 8 random songs as per requirements
                final displaySongs = songs.length > 8
                    ? (songs..shuffle()).take(8).toList()
                    : songs;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: displaySongs.length,
                  itemBuilder: (context, index) {
                    return _buildQuickPlayGridItem(displaySongs[index]);
                  },
                );
              },
            ),
            const SizedBox(height: 40),

            // Just the Hits Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Just the Hits',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to see all hits
                  },
                  child: Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchHitAlbums(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final albums = snapshot.data ?? [];
                return SizedBox(
                  height: 220,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: albums.length,
                    itemBuilder: (context, index) => _buildHitAlbumCard(albums[index]),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),

            // New Releases Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'New Releases',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to see all new releases
                  },
                  child: Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 260, // Increased from 220 to accommodate the content
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: fetchNewReleases(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final releases = snapshot.data ?? [];
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: releases.length,
                    itemBuilder: (context, index) {
                      final release = releases[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: NewReleaseItem(
                          title: release['title'] ?? 'No Title',
                          artist: release['artist'] ?? 'Unknown Artist',
                          imageUrl: release['image_url'] ?? '',
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 40),

            // Recommended Artists Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recommended Artists',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to see all artists
                  },
                  child: Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: fetchArtists(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text(
                        'No artists found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) => _buildArtistCircle(snapshot.data![index]),
                  );
                },
              ),
            ),
            const SizedBox(height: 100), // Space for player
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPlayGridItem(Map<String, dynamic> song) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => playSong(song),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withOpacity(0.05),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Song Image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: song['image_url'] ?? '',
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[850],
                    child: const Icon(Icons.music_note, color: Colors.white54, size: 40),
                  ),
                ),
              ),
              // Gradient overlay for better text visibility
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
              // Play button overlay on hover (can be implemented with MouseRegion)
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white.withOpacity(0.8),
                      size: 24,
                    ),
                  ),
                ),
              ),
              // Song info at bottom
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song['title'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 3,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (song['artist'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        song['artist'],
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 12,
                          shadows: [
                            Shadow(
                              offset: const Offset(0, 1),
                              blurRadius: 3,
                              color: Colors.black,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Keep the original method for backward compatibility
  Widget _buildQuickPlayCard(Map<String, dynamic> song) {
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => playSong(song),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                  child: CachedNetworkImage(
                    imageUrl: song['image_url'] ?? '',
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[850],
                      child: const Icon(Icons.music_note, color: Colors.white54),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song['title'] ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (song['artist'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          song['artist'],
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHitAlbumCard(Map<String, dynamic> album) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumView(
              album: album,
              supabaseClient: supabaseClient,
              onSongSelected: playSong,
              currentlyPlayingSong: _currentSong,
            ),
          ),
        );
      },
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Cover
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Album Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: album['image_url'] ?? '',
                      height: 200,
                      width: 200,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[850],
                        child: const Icon(Icons.album, color: Colors.white54, size: 48),
                      ),
                    ),
                  ),
                  // Play button overlay (visible on hover)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black.withOpacity(0.3),
                      ),
                      child: Center(
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.6),
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Album Info
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album['title'] ?? 'Unknown',
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
                    album['artist'] ?? 'Various Artists',
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
          ],
        )
        ),
    );
  }

  Widget _buildArtistCircle(Map<String, dynamic> artist) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistDetailsPage(artist: artist),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(right: 24),
        child: Column(
          children: [
            // Artist Image with hover effect
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Artist Image
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: artist['image_url'] ?? '',
                      width: 130,
                      height: 130,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[850],
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      // errorWidget: (context, url, error) => Container(
                      //   color: Colors.grey[850],
                      //   child: const Icon(Icons.person, color: Colors.white54, size: 48),
                      // ),
                    ),
                  ),
                  // Hover overlay
                  ClipOval(
                    child: Container(
                      width: 130,
                      height: 130,
                      color: Colors.black.withOpacity(0.2),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.5),
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Artist Name
            Text(
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
          ],
        ),
      ),
    );
  }
}

class NewReleaseItem extends StatefulWidget {
  final String title;
  final String artist;
  final String imageUrl;

  const NewReleaseItem({
    super.key,
    required this.title,
    required this.artist,
    required this.imageUrl,
  });

  @override
  State<NewReleaseItem> createState() => _NewReleaseItemState();
}

class _NewReleaseItemState extends State<NewReleaseItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) => setState(() => _isHovering = true),
      onExit: (event) => setState(() => _isHovering = false),
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Use minimum space needed
          children: [
            // Album Cover
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Album Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      height: 200,
                      width: 200,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[850],
                        child: const Icon(Icons.album, color: Colors.white54, size: 48),
                      ),
                    ),
                  ),
                  // Hover overlay with play button
                  if (_isHovering)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black.withOpacity(0.3),
                        ),
                        child: Center(
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.6),
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // "NEW" badge
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Album Info - more compact
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4), // Reduced top padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // Use minimum space needed
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14, // Reduced font size
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2), // Reduced spacing
                  Text(
                    widget.artist,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12, // Reduced font size
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
    );
  }
}

class ArtistDetailsPage extends StatelessWidget {
  final Map<String, dynamic> artist;

  const ArtistDetailsPage({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(artist['name'] ?? 'Artist', style: const TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artist header with large image
            Stack(
              children: [
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: artist['image_url'] != null
                      ? CachedNetworkImage(
                          imageUrl: artist['image_url'],
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: Colors.grey[850]),
                        )
                      : Container(color: Colors.grey[850]),
                ),
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: Text(
                    artist['name'] ?? 'Artist Name',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Placeholder for tabs (Overview, Popular, Albums)
            const DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Popular'),
                      Tab(text: 'Albums'),
                    ],
                  ),
                  SizedBox(
                    height: 400,
                    child: TabBarView(
                      children: [
                        Center(child: Text('Overview Content', style: TextStyle(color: Colors.white))),
                        Center(child: Text('Popular Songs', style: TextStyle(color: Colors.white))),
                        Center(child: Text('Albums List', style: TextStyle(color: Colors.white))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}