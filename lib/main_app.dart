import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';
import 'album_view.dart';
import 'browse_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'services/audio_service.dart';
import 'layouts/main_layout.dart';
import 'layouts/content_view.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  _MainAppState createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final SupabaseClient supabaseClient = Supabase.instance.client;
  final AudioService _audioService = AudioService();
  Map<String, dynamic>? _currentSong;
  bool _showQueue = false;
  bool _showLyrics = false;
  ContentType _currentContentType = ContentType.home;
  Map<String, dynamic>? _contentData;
  String? _lyrics;
  String? _translatedLyrics;
  Duration _lyricsCurrentPosition = Duration.zero;
  Duration _lyricsTotalDuration = Duration.zero;
  Color _lyricsAccentColor = Colors.green;

  @override
  void initState() {
    super.initState();
    _audioService.currentSongStream.listen((song) {
      debugPrint('[MainApp] Received song from AudioService.currentSongStream: ' + song.toString());
      setState(() {
        _currentSong = song;
      });
    });

    // On app start, set _currentSong if AudioService.currentSong is not null
    if (_audioService.currentSong != null) {
      debugPrint('[MainApp] Setting _currentSong from AudioService.currentSong on startup: ' + _audioService.currentSong.toString());
      _currentSong = _audioService.currentSong;
    }

    // Listen for content navigation events
    ContentViewController().addListener(_handleContentNavigation);
  }

  @override
  void dispose() {
    ContentViewController().removeListener(_handleContentNavigation);
    super.dispose();
  }

  void _handleContentNavigation(ContentType contentType, {Map<String, dynamic>? data}) {
    setState(() {
      _currentContentType = contentType;
      _contentData = data;
    });
  }

  void _toggleQueue(bool show) {
    setState(() {
      _showQueue = show;
      if (show) _showLyrics = false;
    });
  }

  void _openLyricsPanel({
    required String? lyrics,
    String? translatedLyrics,
    required Duration currentPosition,
    required Duration totalDuration,
    required Color accentColor,
  }) {
    setState(() {
      _showLyrics = true;
      _showQueue = false;
      _lyrics = lyrics;
      _translatedLyrics = translatedLyrics;
      _lyricsCurrentPosition = currentPosition;
      _lyricsTotalDuration = totalDuration;
      _lyricsAccentColor = accentColor;
    });
  }

  void _closeLyricsPanel() {
    setState(() {
      _showLyrics = false;
    });
  }

  void _onQueueReordered(List<Map<String, dynamic>> newQueue) {
    if (_currentSong == null) return;
    final updatedSong = {
      ..._currentSong!,
      'queue': newQueue,
    };
    _audioService.playSong(updatedSong);
    setState(() {
      _currentSong = updatedSong;
    });
  }

  void _playSong(Map<String, dynamic> song) {
    _audioService.playSong(song);
  }

  @override
  Widget build(BuildContext context) {
    // Determine which content to show
    Widget content;
    int currentIndex = 0; // Default to home tab

    // Set the current index based on content type
    switch (_currentContentType) {
      case ContentType.home:
        currentIndex = 0;
        break;
      case ContentType.search:
        currentIndex = 1;
        break;
      case ContentType.library:
        currentIndex = 2;
        break;
      case ContentType.profile:
        currentIndex = 3;
        break;
      default:
        // For album, artist, playlist, etc. keep the last selected tab
        break;
    }

    // Determine which content to show based on content type
    switch (_currentContentType) {
      case ContentType.home:
        // Show the home screen
        content = const HomeScreen();
        break;
      case ContentType.search:
        // Show the search/browse screen
        content = BrowseScreen(
          supabaseClient: supabaseClient,
          onSongSelected: _playSong,
          currentlyPlayingSong: _currentSong,
        );
        break;
      case ContentType.library:
        // Show the library screen
        content = LibraryScreen(
          supabaseClient: supabaseClient,
          currentlyPlayingSong: _currentSong,
        );
        break;
      case ContentType.profile:
        // Show the profile screen
        content = SettingsScreen(
          supabaseClient: supabaseClient,
        );
        break;
      case ContentType.album:
      case ContentType.playlist:
      case ContentType.artist:
        // For album/playlist/artist views, use ContentView
        content = ContentView(
          initialContentType: _currentContentType,
          contentData: _contentData,
          supabaseClient: supabaseClient,
          onSongSelected: _playSong,
          currentlyPlayingSong: _currentSong,
          audioService: _audioService,
          onBackPressed: () {
            // Handle back navigation
            setState(() {
              _currentContentType = ContentType.home;
              _contentData = null;
            });
          },
        );
        break;
      default:
        // Default to home screen
        content = const HomeScreen();
    }

    // Wrap everything in MainLayout to ensure consistent UI
    Widget mainLayoutContent = MainLayout(
      currentIndex: currentIndex,
      currentSong: _currentSong,
      audioService: _audioService,
      onSongSelected: _playSong,
      onNavItemSelected: (index) {
        // Handle navigation item selection based on the index
        setState(() {
          switch (index) {
            case 0: // Home
              _currentContentType = ContentType.home;
              break;
            case 1: // Search
              _currentContentType = ContentType.search;
              break;
            case 2: // Library
              _currentContentType = ContentType.library;
              break;
            case 3: // Profile
              _currentContentType = ContentType.profile;
              break;
            default:
              _currentContentType = ContentType.home;
          }
          _contentData = null; // Reset content data when switching main sections
        });
      },
      showQueue: _showQueue,
      onQueueToggle: _toggleQueue,
      showLyrics: _showLyrics,
      openLyricsPanel: _openLyricsPanel,
      closeLyricsPanel: _closeLyricsPanel,
      lyrics: _lyrics,
      translatedLyrics: _translatedLyrics,
      lyricsCurrentPosition: _lyricsCurrentPosition,
      lyricsTotalDuration: _lyricsTotalDuration,
      lyricsAccentColor: _lyricsAccentColor,
      onQueueReordered: _onQueueReordered,
      child: content,
    );

    return MaterialApp(
      title: 'Music App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0C0F14),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: mainLayoutContent,
    );
  }
}
