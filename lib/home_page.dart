import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io'; // Add this import for InternetAddress
import 'browse_screen.dart';
import 'album_view.dart';
import 'services/audio_service.dart';
import 'services/jam_session_service.dart';
import 'services/dynamic_playlist_service.dart';
import 'services/listening_time_service.dart';
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
import 'package:palette_generator/palette_generator.dart';
import 'services/backblaze_service.dart';
import 'widgets/quick_play_section.dart';

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
  final BackblazeService _backblazeService = BackblazeService();
  final ListeningTimeService _listeningTimeService = ListeningTimeService();
  final Map<String, Map<String, dynamic>> _songCache = {};

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
    _initializeListeningTimeService();

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

  // Initialize listening time service
  void _initializeListeningTimeService() async {
    await _listeningTimeService.initialize();
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
      // Cache songs
      for (var song in response) {
        _songCache[song['id'].toString()] = song;
      }
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
      print('HomeScreen: Fetching downloaded albums');
      final albums = await _audioService.getDownloadedAlbums();
      print('HomeScreen: Received ${albums.length} downloaded albums from AudioService');

      // Check if we're online
      bool isOnline = true;
      try {
        final result = await InternetAddress.lookup('google.com');
        isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (e) {
        isOnline = false;
      }

      print('HomeScreen: Online status: $isOnline');

      // If we're offline, add a flag to indicate this
      if (!isOnline) {
        for (var album in albums) {
          album['offline_mode'] = true;
        }
      }

      // Log album details for debugging
      for (var album in albums) {
        print('HomeScreen: Downloaded album - ID: ${album['id']}, Title: ${album['title']}');
      }

      return albums;
    } catch (e) {
      print('HomeScreen: Error fetching downloaded albums: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchRecentlyPlayed() async {
    try {
      final response = await supabaseClient
          .from('user_play_history')
          .select('*, songs(*)')
          .order('played_at', ascending: false);

      if (response.isEmpty) {
        return [];
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching recently played: $e');
      return [];
    }
  }
  Future<List<Map<String, dynamic>>> fetchTrendingNow() async {
    try {
      final response = await supabaseClient
          .from('songs_2')
          .select('id, title, artist, audio_url, image_url, duration, play_count') // 'song_lyrics' commented out
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

  // NEW: fetch new releases from a "albums" table with category "album, new releases"
  Future<List<Map<String, dynamic>>> fetchNewReleases() async {
    try {
      final response = await supabaseClient
          .from('albums')
          .select('*, id')
          .eq('category', 'album, new releases')
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
                      _audioService.playSong(song, restorePosition: false);
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

  void playSong(Map<String, dynamic> song) async {
    try {
      final songId = song['id'].toString();
      Map<String, dynamic> songData = song;
      if (_songCache.containsKey(songId)) {
        songData = _songCache[songId]!;
      }
      // Get the audio URL from Backblaze if needed
      final audioUrl = await _backblazeService.getAudioUrl(
        songData['audio_url'],
        songData['file_identifier'],
      );
      print('Resolved audio URL: $audioUrl'); // Debug log

      // Create complete song context with queue
      final songWithContext = {
        ...Map<String, dynamic>.from(songData),
        'queue': [], // Initialize empty queue if none exists
        'audio_url': audioUrl, // Use the resolved audio URL
        'image_url': songData['image_url'] ?? '', // Keep original image_url for now
        'artist': songData['artist'] ?? 'Unknown Artist',
        'title': songData['title'] ?? 'Unknown Title',
      };

      // Play the song
      _audioService.playSong(songWithContext, restorePosition: false);
    } catch (e) {
      print('Error resolving audio URL: $e'); // Debug log
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
                _navigateToAlbum({
                  ...playlist,
                  'playlist_name': playlist['name'] ?? playlist['playlist_name'] ?? playlist['title'],
                  'title': playlist['name'] ?? playlist['playlist_name'] ?? playlist['title'],
                });
              },
            ),
            const SizedBox(height: 40),

            // Quick Play Section
            QuickPlaySection(
              onSongSelected: (song) {
                _audioService.playSong(song, restorePosition: false);
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
                // TextButton(
                //   onPressed: () {
                //     // Navigate to see all hits
                //   },
                //   child: Text(
                //     'See All',
                //     style: TextStyle(
                //       fontSize: 14,
                //       color: Colors.grey[400],
                //     ),
                //   ),
                // ),
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
                // TextButton(
                //   onPressed: () {
                //     // Navigate to see all new releases
                //   },
                //   child: Text(
                //     'See All',
                //     style: TextStyle(
                //       fontSize: 14,
                //       color: Colors.grey[400],
                //     ),
                //   ),
                // ),
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
                  final albums = snapshot.data ?? [];
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: GestureDetector(
                          onTap: () {
                            ContentViewController().navigateTo(
                              ContentType.album,
                              data: {
                                ...album,
                                'id': album['id'], // Ensure ID is passed
                                'title': album['title'] ?? 'Unknown Album',
                                'artist': album['artist'] ?? 'Unknown Artist',
                                'image_url': album['image_url'],
                                'category': album['category'] ?? 'album'
                              },
                            );
                          },
                          child: NewReleaseItem(
                            title: album['title'] ?? 'No Title',
                            artist: album['artist'] ?? 'Unknown Artist',
                            imageUrl: album['image_url'] ?? '',
                            fileIdentifier: album['file_identifier'],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 40),

            // Downloaded Albums Section
            // Row(
            //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
            //   children: [
            //     Text(
            //       'Downloaded Albums',
            //       style: GoogleFonts.montserrat(
            //         fontSize: 22,
            //         fontWeight: FontWeight.w300,
            //         color: Colors.white,
            //       ),
            //     ),
            //     TextButton(
            //       onPressed: () {
            //         // Navigate to see all downloaded albums
            //       },
            //       child: Text(
            //         'See All',
            //         style: TextStyle(
            //           fontSize: 14,
            //           color: Colors.grey[400],
            //         ),
            //       ),
            //     ),
            //   ],
            // ),
            // const SizedBox(height: 16),
            // SizedBox(
            //   height: 260,
            //   child: FutureBuilder<List<Map<String, dynamic>>>(
            //     future: fetchDownloadedAlbums(),
            //     builder: (context, snapshot) {
            //       if (snapshot.connectionState == ConnectionState.waiting) {
            //         return const Center(child: CircularProgressIndicator());
            //       }

            //       final albums = snapshot.data ?? [];

            //       if (albums.isEmpty) {
            //         return Center(
            //           child: Column(
            //             mainAxisAlignment: MainAxisAlignment.center,
            //             children: [
            //               Icon(Icons.download_done, size: 48, color: Colors.grey[600]),
            //               const SizedBox(height: 16),
            //               Text(
            //                 'No downloaded albums yet',
            //                 style: TextStyle(color: Colors.grey[400], fontSize: 16),
            //               ),
            //               const SizedBox(height: 8),
            //               Text(
            //                 'Download albums to listen offline',
            //                 style: TextStyle(color: Colors.grey[600], fontSize: 14),
            //               ),
            //             ],
            //           ),
            //         );
            //       }

            //       return ListView.builder(
            //         scrollDirection: Axis.horizontal,
            //         itemCount: albums.length,
            //         itemBuilder: (context, index) {
            //           final album = albums[index];
            //           return _buildHitAlbumCard(album);
            //         },
            //       );
            //     },
            //   ),
            // ),
            // const SizedBox(height: 40),

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
                // TextButton(
                //   onPressed: () {
                //     // Navigate to see all artists
                //   },
                //   child: Text(
                //     'See All',
                //     style: TextStyle(
                //       fontSize: 14,
                //       color: Colors.grey[400],
                //     ),
                //   ),
                // ),
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

  Widget _buildHitAlbumCard(Map<String, dynamic> album) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovering = false;
        return MouseRegion(
          onEnter: (_) => setState(() => isHovering = true),
          onExit: (_) => setState(() => isHovering = false),
          child: GestureDetector(
            onTap: () {
              _navigateToAlbum(album);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.identity()..scale(isHovering ? 1.05 : 1.0),
              child: Container(
                width: 200,
                height: 250,
                margin: const EdgeInsets.only(right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Album Cover with Backblaze support
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isHovering ? 0.4 : 0.2),
                            blurRadius: isHovering ? 15 : 10,
                            offset: Offset(0, isHovering ? 8 : 5),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Album Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FutureBuilder<String>(
                              future: _backblazeService.getImageUrl(
                                album['image_url'],
                                album['file_identifier'],
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return Container(
                                    color: Colors.grey[850],
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                if (snapshot.hasError) {
                                  return Container(
                                    color: Colors.grey[850],
                                    child: const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                                  );
                                }

                                return CachedNetworkImage(
                                  imageUrl: snapshot.data!,
                                  height: 200,
                                  width: 200,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: Colors.grey[850],
                                    child: const Icon(Icons.album, color: Colors.white54, size: 48),
                                  ),
                                );
                              },
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
                          if (album['downloaded'] == true)
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
            ),
          ),
        );
      }
    );
  }

  Widget _buildArtistCircle(Map<String, dynamic> artist) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovering = false;
        return MouseRegion(
          onEnter: (_) => setState(() => isHovering = true),
          onExit: (_) => setState(() => isHovering = false),
          child: GestureDetector(
            onTap: () {
              ContentViewController().navigateTo(
                ContentType.artist,
                data: artist,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.identity()..scale(isHovering ? 1.1 : 1.0),
              child: Container(
                margin: const EdgeInsets.only(right: 24),
                child: Column(
                  children: [
                    // Artist Image with Backblaze support
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isHovering ? 0.4 : 0.2),
                            blurRadius: isHovering ? 15 : 10,
                            offset: Offset(0, isHovering ? 8 : 5),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Artist Image
                          ClipOval(
                            child: FutureBuilder<String>(
                              future: _backblazeService.getImageUrl(
                                artist['image_url'],
                                artist['file_identifier'],
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return Container(
                                    color: Colors.grey[850],
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                if (snapshot.hasError) {
                                  return Container(
                                    color: Colors.grey[850],
                                    child: const Icon(Icons.person, color: Colors.white54, size: 48),
                                  );
                                }

                                return CachedNetworkImage(
                                  imageUrl: snapshot.data!,
                                  width: 130,
                                  height: 130,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey[850],
                                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[850],
                                    child: const Icon(Icons.person, color: Colors.white54, size: 48),
                                  ),
                                );
                              },
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
            ),
          ),
        );
      }
    );
  }
}

class NewReleaseItem extends StatefulWidget {
  final String title;
  final String artist;
  final String imageUrl;
  final String? fileIdentifier; // Add fileIdentifier parameter

  const NewReleaseItem({
    super.key,
    required this.title,
    required this.artist,
    required this.imageUrl,
    this.fileIdentifier,
  });

  @override
  State<NewReleaseItem> createState() => _NewReleaseItemState();
}

class _NewReleaseItemState extends State<NewReleaseItem> {
  bool _isHovering = false;
  final BackblazeService _backblazeService = BackblazeService();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) => setState(() => _isHovering = true),
      onExit: (event) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.identity()..scale(_isHovering ? 1.05 : 1.0),
        child: SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Album Cover with Backblaze support
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isHovering ? 0.4 : 0.2),
                      blurRadius: _isHovering ? 15 : 10,
                      offset: Offset(0, _isHovering ? 8 : 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Album Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FutureBuilder<String>(
                        future: _backblazeService.getImageUrl(
                          widget.imageUrl,
                          widget.fileIdentifier,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Container(
                              color: Colors.grey[850],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return Container(
                              color: Colors.grey[850],
                              child: const Icon(Icons.album, color: Colors.white54, size: 48),
                            );
                          }

                          return CachedNetworkImage(
                            imageUrl: snapshot.data!,
                            height: 200,
                            width: 200,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[850],
                              child: const Icon(Icons.album, color: Colors.white54, size: 48),
                            ),
                          );
                        },
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
      ),
    );
  }
}

class ArtistDetailsPage extends StatefulWidget {
  final Map<String, dynamic> artist;
  final VoidCallback? onBackPressed; // Add callback for back navigation

  const ArtistDetailsPage({
    super.key,
    required this.artist,
    this.onBackPressed,
  });

  @override
  State<ArtistDetailsPage> createState() => _ArtistDetailsPageState();
}

class _ArtistDetailsPageState extends State<ArtistDetailsPage> {
  final SupabaseClient supabaseClient = Supabase.instance.client;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  Color _dominantColor = Colors.black;
  bool _isLoadingColor = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _extractDominantColor();
    _checkIfFollowing();
  }
  Future<void> _checkIfFollowing() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) return;
    // Get artist id from "artists" table using artist name if not present
    String? artistId = widget.artist['id'];
    if (artistId == null) {
      final artistRow = await supabaseClient
          .from('artists')
          .select('id')
          .eq('name', widget.artist['name'])
          .maybeSingle();
      artistId = artistRow != null ? artistRow['id'] as String? : null;
    }
    if (artistId == null) {
      setState(() {
        _isFollowing = false;
      });
      return;
    }
    // Check if user is following this artist in artist_followers table
    final response = await supabaseClient
        .from('artist_followers')
        .select()
        .eq('artist_id', artistId)
        .eq('user_id', user.id)
        .maybeSingle();
    setState(() {
      _isFollowing = response != null;
    });
    // Save artist id to widget.artist for later use
    widget.artist['id'] = artistId;
  }

  Future<void> _toggleFollowSupabase() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) return;
    setState(() {
      _isFollowLoading = true;
    });
    // Get artist id from "artists" table using artist name if not present
    String? artistId = widget.artist['id'];
    if (artistId == null) {
      final artistRow = await supabaseClient
          .from('artists')
          .select('id')
          .eq('name', widget.artist['name'])
          .maybeSingle();
      artistId = artistRow != null ? artistRow['id'] as String? : null;
    }
    if (artistId == null) {
      setState(() {
        _isFollowLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Artist not found.')),
      );
      return;
    }
    widget.artist['id'] = artistId;
    if (_isFollowing) {
      // Unfollow
      await supabaseClient
          .from('artist_followers')
          .delete()
          .eq('artist_id', artistId)
          .eq('user_id', user.id);
      setState(() {
        _isFollowing = false;
        _isFollowLoading = false;
      });
    } else {
      // Follow
      await supabaseClient.from('artist_followers').insert({
        'artist_id': artistId,
        'user_id': user.id,
      });
      setState(() {
        _isFollowing = true;
        _isFollowLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _extractDominantColor() async {
    if (widget.artist['image_url'] == null) {
      setState(() {
        _isLoadingColor = false;
      });
      return;
    }

    try {
      final imageProvider = NetworkImage(widget.artist['image_url']);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(200, 200),
      );

      setState(() {
        _dominantColor = paletteGenerator.dominantColor?.color ?? Colors.black;
        _isLoadingColor = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingColor = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchArtistTopTracks() async {
    try {
      // Fetch songs for this artist where isTop is TRUE
      final response = await supabaseClient
          .from('songs_2')
          .select('id, title, artist, duration, audio_url, image_url, play_count') // 'song_lyrics' commented out
          .eq('artist', widget.artist['name'])
          .eq('isTop', true)
          .order('play_count', ascending: false)
          .limit(5);

      final tracks = List<Map<String, dynamic>>.from(response);

      // If no top tracks found, get any tracks from this artist
      if (tracks.isEmpty) {
        final fallbackResponse = await supabaseClient
            .from('songs_2')
            .select('id, title, artist, duration, audio_url, image_url, play_count') // 'song_lyrics' commented out
            .eq('artist', widget.artist['name'])
            .order('play_count', ascending: false)
            .limit(5);

        return List<Map<String, dynamic>>.from(fallbackResponse);
      }

      return tracks;
    } catch (e) {
      print('Error fetching artist top tracks: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchArtistAlbums() async {
    try {
      // In a real app, you would fetch the artist's albums
      // For now, we'll return a placeholder list
      return List.generate(6, (index) => {
        'id': 'album_$index',
        'title': 'Album ${index + 1}',
        'artist': widget.artist['name'] ?? 'Unknown Artist',
        'release_date': '202${4 - (index % 5)}',
        'image_url': widget.artist['image_url'],
      });
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSimilarArtists() async {
    try {
      // In a real app, you would fetch similar artists
      // For now, we'll return a placeholder list
      return List.generate(6, (index) => {
        'id': 'artist_$index',
        'name': 'Similar Artist ${index + 1}',
        'image_url': 'https://picsum.photos/200/200?random=${index + 10}',
      });
    } catch (e) {
      return [];
    }
  }

  void _toggleFollow() {
    _toggleFollowSupabase();
  }

  // Method to fetch the artist's biography from Supabase
  Future<String> _fetchArtistBio() async {
    try {
      // Get the artist name from the widget
      final artistName = widget.artist['name'];

      if (artistName == null) {
        return 'No biography available for this artist.';
      }

      // Query the artist_page table for the artist_details column
      final response = await supabaseClient
          .from('artist_page')
          .select('artist_details')
          .eq('artist_name', artistName)
          .maybeSingle();

      if (response == null) {
        return 'No biography available for this artist.';
      }

      // Extract the bio from the response
      final bio = response['artist_details'] as String?;

      if (bio == null || bio.isEmpty) {
        return 'No biography available for this artist.';
      }

      return bio;
    } catch (e) {
      print('Error fetching artist bio: $e');
      return 'Unable to load artist biography at this time.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    final headerHeight = isDesktop ? 400.0 : 300.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (widget.onBackPressed != null) {
              // Use the callback for in-app navigation
              widget.onBackPressed!();
            } else {
              // Only try to pop if we're in a regular navigation stack
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {
              // Show more options
            },
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Artist header with large image
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Background image with gradient overlay
                ShaderMask(
                  shaderCallback: (rect) {
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ).createShader(Rect.fromLTRB(0, 0, rect.width, rect.height));
                  },
                  blendMode: BlendMode.dstIn,
                  child: Container(
                    height: headerHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _isLoadingColor ? Colors.grey[900] : _dominantColor.withOpacity(0.5),
                    ),
                    child: widget.artist['image_url'] != null
                      ? CachedNetworkImage(
                          imageUrl: widget.artist['image_url'],
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: Colors.grey[850]),
                        )
                      : Container(color: Colors.grey[850]),
                  ),
                ),

                // Gradient overlay
                Container(
                  height: headerHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        _isLoadingColor
                          ? const Color(0xFF0C0F14)
                          : _dominantColor.withOpacity(0.3),
                        const Color(0xFF0C0F14),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),

                // Artist info
                Positioned(
                  bottom: 20,
                  left: isDesktop ? 40 : 20,
                  right: isDesktop ? 40 : 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Verified badge
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Verified Artist',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Artist name
                      Text(
                        widget.artist['name'] ?? 'Artist Name',
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontSize: isDesktop ? 72 : 42,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),

                      // Monthly listeners
                      const SizedBox(height: 8),
                      Text(
                        '8,282,123 monthly listeners',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: isDesktop ? 16 : 14,
                        ),
                      ),

                      // Action buttons
                      const SizedBox(height: 24),
                      if (isDesktop)
                        Row(
                          children: [
                            // Play button
                            ElevatedButton(
                              onPressed: () {
                                // Play artist's popular songs
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                ),
                              ),
                              child: const Text(
                                'Play',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Follow button
                      OutlinedButton(
                        onPressed: _isFollowLoading ? null : _toggleFollow,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.grey),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                          ),
                        ),
                        child: _isFollowLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isFollowing ? 'Following' : 'Follow',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                            const SizedBox(width: 16),

                            // More options
                            IconButton(
                              icon: const Icon(Icons.more_horiz, color: Colors.white),
                              onPressed: () {
                                // Show more options
                              },
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            // Follow button
                      OutlinedButton(
                        onPressed: _isFollowLoading ? null : _toggleFollow,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                          ),
                        ),
                        child: _isFollowLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isFollowing ? 'Following' : 'Follow',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                            const SizedBox(width: 16),

                            // Play button (circular)
                            FloatingActionButton(
                              onPressed: () {
                                // Play artist's popular songs
                              },
                              backgroundColor: Colors.green,
                              child: const Icon(Icons.play_arrow),
                            ),
                            const Spacer(),

                            // Shuffle button
                            IconButton(
                              icon: const Icon(Icons.shuffle, color: Colors.white),
                              onPressed: () {
                                // Shuffle artist's songs
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content sections
          SliverToBoxAdapter(
            child: Container(
              color: const Color(0xFF0C0F14),
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 40 : 20,
                vertical: 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Popular section
                  Text(
                    'Popular',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Popular tracks
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchArtistTopTracks(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final tracks = snapshot.data ?? [];

                      return Column(
                        children: List.generate(
                          tracks.length,
                          (index) => _buildTrackItem(tracks[index], index + 1),
                        ),
                      );
                    },
                  ),

                  // See more button
                  // Center(
                  //   child: TextButton(
                  //     onPressed: () {
                  //       // Show all tracks
                  //     },
                  //     child: Text(
                  //       'See more',
                  //       style: TextStyle(
                  //         color: Colors.grey[400],
                  //         fontSize: 14,
                  //       ),
                  //     ),
                  //   ),
                  // ),

                  const SizedBox(height: 48),

                  // Discography section
                  Text(
                    'Discography',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),

                  // Albums grid
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchArtistAlbums(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final albums = snapshot.data ?? [];

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isDesktop ? 6 : 2,
                          childAspectRatio: 0.7,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: albums.length,
                        itemBuilder: (context, index) {
                          return _buildAlbumItem(albums[index]);
                        },
                      );
                    },
                  ),

                  // See discography button
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: OutlinedButton(
                        onPressed: () {
                          // Show all albums
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.grey),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                          ),
                        ),
                        child: const Text(
                          'See discography',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Fans also like section
                  Text(
                    'Fans also like',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Similar artists
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchSimilarArtists(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final artists = snapshot.data ?? [];

                      return SizedBox(
                        height: 180,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: artists.length,
                          itemBuilder: (context, index) {
                            return Container(
                              width: 120,
                              margin: const EdgeInsets.only(right: 16),
                              child: _buildArtistItem(artists[index]),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  // About section
                  const SizedBox(height: 48),
                  Text(
                    'About',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Artist bio
                    FutureBuilder<String>(
                    future: _fetchArtistBio(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)
                        ),
                      );
                      }

                      final bio = snapshot.data ?? 'No biography available for this artist.';

                      return Text(
                      bio,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 16,
                        height: 1.5,
                      ),
                      );
                    },
                    ),

                  // Monthly listeners with icon
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(Icons.people, color: Colors.grey[400], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '8,282,123 monthly listeners',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),

                  // Extra space at bottom for player
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackItem(Map<String, dynamic> track, int position) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () {
          // Play this track
        },
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            // Position number
            SizedBox(
              width: 30,
              child: Text(
                position.toString(),
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 16),

            // Track image
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: track['image_url'] ?? '',
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 50,
                  height: 50,
                  color: Colors.grey[850],
                  child: const Icon(Icons.music_note, color: Colors.white54, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track['title'] ?? 'Unknown Track',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${track['plays'] != null ? '${(int.tryParse(track['plays']) ?? 0) / 1000000}M' : ''} plays',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Duration
            Text(
              track['duration'] ?? '',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 16),

            // More options
            IconButton(
              icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 20),
              onPressed: () {
                // Show track options
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumItem(Map<String, dynamic> album) {
    return InkWell(
      onTap: () {
        // Navigate to album
      },
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Album cover
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: album['image_url'] ?? '',
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[850],
                  child: const Icon(Icons.album, color: Colors.white54, size: 40),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Album title
          SizedBox(
            height: 20, // Fixed height for title
            child: Text(
              album['title'] ?? 'Unknown Album',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),

          // Album year
          SizedBox(
            height: 16, // Fixed height for year
            child: Text(
              album['release_date'] ?? '',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistItem(Map<String, dynamic> artist) {
    return InkWell(
      onTap: () {
        // Use the ContentViewController to navigate to the artist view
        // This keeps the main layout consistent (sidebar and player)
        ContentViewController().navigateTo(
          ContentType.artist,
          data: artist,
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Artist image (circular)
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: artist['image_url'] ?? '',
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[850],
                  child: const Icon(Icons.person, color: Colors.white54, size: 40),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Artist name
          Text(
            artist['name'] ?? 'Unknown Artist',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),

          // Artist type
          Text(
            'Artist',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}