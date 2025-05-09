import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';
import 'album_view.dart';
import 'services/audio_service.dart';
import 'layouts/main_layout.dart';
import 'layouts/content_view.dart';

class MainApp extends StatefulWidget {
  const MainApp({Key? key}) : super(key: key);

  @override
  _MainAppState createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final SupabaseClient supabaseClient = Supabase.instance.client;
  final AudioService _audioService = AudioService();
  Map<String, dynamic>? _currentSong;
  bool _showQueue = false;
  ContentType _currentContentType = ContentType.home;
  Map<String, dynamic>? _contentData;

  @override
  void initState() {
    super.initState();
    _audioService.currentSongStream.listen((song) {
      setState(() {
        _currentSong = song;
      });
    });

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

    if (_currentContentType == ContentType.home) {
      // Show the home screen
      content = const HomeScreen();
    } else {
      // For album/playlist views, use ContentView
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
    }

    // Wrap everything in MainLayout to ensure consistent UI
    Widget mainLayoutContent = MainLayout(
      currentIndex: currentIndex,
      currentSong: _currentSong,
      audioService: _audioService,
      onSongSelected: _playSong,
      onNavItemSelected: (index) {
        // Handle navigation item selection
        setState(() {
          _currentContentType = ContentType.home;
          _contentData = null;
        });
      },
      showQueue: _showQueue,
      onQueueToggle: _toggleQueue,
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
