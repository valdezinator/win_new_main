import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io'; // Add this import for InternetAddress
import 'browse_screen.dart';
import 'album_view.dart';
import 'services/audio_service.dart';
import 'services/jam_session_service.dart';
import 'services/dynamic_playlist_service.dart';
import 'library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'profile_screen.dart';
import 'layouts/content_view.dart';
import 'widgets/dynamic_playlists_section.dart';
import 'package:google_fonts/google_fonts.dart'; // <-- Add this import

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic>? initialSong;
  final bool autoplay;
  final int initialTabIndex;

  const HomeScreen({
    super.key,
    this.initialSong,
    this.autoplay = false,
    this.initialTabIndex = 0,
  });

  @override
    State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Use the global Supabase instance to ensure authentication state is shared
  final SupabaseClient supabaseClient = Supabase.instance.client;
  late TabController _tabController;
  Map<String, dynamic>? _currentSong;
  bool showQueue = false;
  final AudioService _audioService = AudioService();
  final DynamicPlaylistService _dynamicPlaylistService = DynamicPlaylistService(Supabase.instance.client);

  // Add user name - this would normally come from your auth service
  final String userName = "Peter";
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});  // Rebuild to update box colors
      }
    });
    _setupAudioListener();
    _initializeLastPlayedSong();
    _initializeJamSessionService();
    _initializeDynamicPlaylistService();

    // Debug: Check authentication state
    final user = supabaseClient.auth.currentUser;
    print('HomeScreen - Current user: ${user?.id}');
    print('HomeScreen - Is authenticated: ${user != null}');
  }

  void _initializeDynamicPlaylistService() async {
    await _dynamicPlaylistService.initialize();
  }

  // Initialize JamSessionService with the current user ID
  void _initializeJamSessionService() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await JamSessionService().initialize(userId);
    }
  }

  StreamSubscription? _audioSubscription;

  void _setupAudioListener() {
    _audioSubscription = _audioService.currentSongStream.listen((song) {
      if (mounted) {
        setState(() => _currentSong = song);
      }
    });
  }

  void _initializeLastPlayedSong() async {
    if (widget.initialSong != null) {
      setState(() => _currentSong = widget.initialSong);
      // Removed auto-play code
    }
  }

  @override
  void dispose() {
    // Cancel audio subscription
    _audioSubscription?.cancel();

    // Dispose controllers
    _tabController.dispose();
    _dynamicPlaylistService.dispose();

    // Save current song state after disposing
    if (_currentSong != null) {
      // Use a separate async function to handle the async operations
      _saveSongState();
    }

    // Call super.dispose() last
    super.dispose();
  }

  // Separate async method to save song state
  Future<void> _saveSongState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_played_song', json.encode(_currentSong));
    await prefs.setBool('was_playing', _audioService.isPlaying);
  }
  Future<List<Map<String, dynamic>>> fetchSongs() async {
    try {
      final response = await supabaseClient
          .from('songs_2')
          .select('id, title, artist, audio_url, image_url, duration')
          .order('created_at');

      if (response.isEmpty) {
        throw Exception('No data received from Supabase');
      }

      print('Fetched ${(response as List).length} songs from songs_2 table');

      return List<Map<String, dynamic>>.from(response);
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

      if (response.isEmpty) {
        throw Exception('No hit albums found');
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchDownloadedAlbums() async {
    try {
      final albums = await _audioService.getDownloadedAlbums();

      // Check if we're online
      bool isOnline = true;
      try {
        final result = await InternetAddress.lookup('google.com');
        isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (e) {
        isOnline = false;
      }

      // If we're offline, add a flag to indicate this
      if (!isOnline) {
        for (var album in albums) {
          album['offline_mode'] = true;
        }
      }

      return albums;
    } catch (e) {
      return [];
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
      //print('Error fetching recently played: $e');
      return [];
    }
  }
  Future<List<Map<String, dynamic>>> fetchTrendingNow() async {
    try {
      final response = await supabaseClient
          .from('songs_2')
          .select('id, title, artist, audio_url, image_url, duration, play_count')
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
          //print('Jamendo API error: ${jamendoResponse.statusCode}');
        }
      }
      return trendingList;
    } catch (e) {
      //print('Error fetching trending songs: $e');
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
      //print('Error fetching genres: $e');
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
      //print('Error fetching artists: $e');
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
      //print('Error fetching new releases: $e');
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
                              style: GoogleFonts.montserrat(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w300,
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
      // Ensure we have all required fields
      if (song['audio_url'] == null) {
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

      // Play the song - this will update the UI through the stream listener
      _audioService.playSong(songWithContext);
    } catch (e) {
      // Show error to user
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

  // Method to navigate to album view using the ContentViewController
  void _navigateToAlbum(Map<String, dynamic> album) {
    // Use the ContentViewController to navigate to the album view
    ContentViewController().navigateTo(
      ContentType.album,
      data: album,
    );
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
                  fontWeight: isSelected ? FontWeight.w300 : FontWeight.normal,
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
    // Create the content for the TabBarView
    return TabBarView(
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
          onAlbumSelected: _navigateToAlbum,
        ),
        SettingsScreen(supabaseClient: supabaseClient),
      ],
    );
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24.0, 24.0, 24.0, _currentSong != null ? 124.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Greeting Section
            Text(
              'Greetings, $userName',
              style: GoogleFonts.montserrat(
                fontSize: 32,
                fontWeight: FontWeight.w300,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 32),

            // Dynamic Playlists Section
            DynamicPlaylistsSection(
              onPlaylistSelected: (playlist) {
                // Authentication is already checked in DynamicPlaylistsSection
                // before this callback is called

                // Use ContentViewController to navigate to the playlist view
                // This keeps the main layout consistent (sidebar and player)
                _navigateToAlbum(playlist);
              },
            ),
            const SizedBox(height: 40),

            // Quick Play Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Quick Play',
                  style: GoogleFonts.montserrat(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
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
            ),            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchSongs(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  //print('Error in Quick Play: ${snapshot.error}');
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
                final displaySongs = songs.length > 8
                    ? (songs..shuffle()).take(8).toList()
                    : songs;

                return SizedBox(
                  height: 230,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: displaySongs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: _buildQuickPlayCard(displaySongs[index]),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 40),

            // Just the Hits Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Just the Hits',
                  style: GoogleFonts.montserrat(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
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
                  height: 250,
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
                Text(
                  'New Releases',
                  style: GoogleFonts.montserrat(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
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

            // Downloaded Albums Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Downloaded Albums',
                  style: GoogleFonts.montserrat(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to see all downloaded albums
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
              height: 260,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: fetchDownloadedAlbums(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final albums = snapshot.data ?? [];

                  if (albums.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_done, size: 48, color: Colors.grey[600]),
                          const SizedBox(height: 16),
                          Text(
                            'No downloaded albums yet',
                            style: TextStyle(color: Colors.grey[400], fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Download albums to listen offline',
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return _buildHitAlbumCard(album);
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
                Text(
                  'Recommended Artists',
                  style: GoogleFonts.montserrat(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
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

  Widget _buildQuickPlayCard(Map<String, dynamic> song) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => playSong(song),
        child: Container(
          width: 180,
          height: 250, // Fixed height to prevent overflow
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album Art
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                child: Image.network(
                  song['image_url'] ?? '',
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 180,
                      height: 180,
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(Icons.music_note, color: Colors.white, size: 40),
                      ),
                    );
                  },
                ),
              ),              // Song Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // Reduced vertical padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 20, // Fixed height for title
                      child: Text(
                        song['title'] ?? 'Unknown Title',
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1, // Reduced to 1 line
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 1), // Reduced height
                    SizedBox(
                      height: 16, // Fixed height for artist
                      child: Text(
                        song['artist'] ?? 'Unknown Artist',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildHitAlbumCard(Map<String, dynamic> album) {
    final bool isDownloaded = album['downloaded'] == true || album['category']?.toString().contains('downloaded') == true;

    return GestureDetector(
      onTap: () {
        // Use the ContentViewController to navigate to the album view
        _navigateToAlbum(album);
      },
      child: Container(
        width: 200,
        height: 250, // Fixed height to prevent overflow
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Add mainAxisSize.min to prevent overflow
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
                  // Show download badge if album is downloaded
                  if (isDownloaded)
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
              ),
            ),
            // Album Info
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4), // Reduced top padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // Add mainAxisSize.min to prevent overflow
                children: [
                  SizedBox(
                    height: 20, // Fixed height for title
                    child: Text(
                      album['title'] ?? 'Unknown',
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontSize: 14, // Reduced font size
                        fontWeight: FontWeight.w300,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2), // Reduced height
                  SizedBox(
                    height: 16, // Fixed height for artist
                    child: Text(
                      album['artist'] ?? 'Various Artists',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12, // Reduced font size
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 14, // Reduced font size
                      fontWeight: FontWeight.w300,
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
                    style: GoogleFonts.montserrat(
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