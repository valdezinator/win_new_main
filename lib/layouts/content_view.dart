import 'package:flutter/material.dart';
import '../album_view.dart';
import '../home_page.dart';
import '../services/audio_service.dart';
import 'package:supabase/supabase.dart';

enum ContentType {
  home,
  search,
  library,
  profile,
  album,
  artist,
  playlist,
}

class ContentView extends StatefulWidget {
  final ContentType initialContentType;
  final Map<String, dynamic>? contentData;
  final SupabaseClient supabaseClient;
  final Function(Map<String, dynamic>) onSongSelected;
  final Map<String, dynamic>? currentlyPlayingSong;
  final AudioService audioService;
  final VoidCallback? onBackPressed;

  const ContentView({
    Key? key,
    required this.initialContentType,
    this.contentData,
    required this.supabaseClient,
    required this.onSongSelected,
    this.currentlyPlayingSong,
    required this.audioService,
    this.onBackPressed,
  }) : super(key: key);

  @override
  _ContentViewState createState() => _ContentViewState();
}

class _ContentViewState extends State<ContentView> {
  late ContentType _currentContentType;
  Map<String, dynamic>? _contentData;

  @override
  void initState() {
    super.initState();
    _currentContentType = widget.initialContentType;
    _contentData = widget.contentData;
  }

  void navigateTo(ContentType contentType, {Map<String, dynamic>? data}) {
    setState(() {
      _currentContentType = contentType;
      _contentData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentContentType) {
      case ContentType.album:
      case ContentType.playlist:
        if (_contentData == null) {
          return const Center(child: Text('No album data', style: TextStyle(color: Colors.white)));
        }
        return AlbumView(
          album: _contentData!,
          supabaseClient: widget.supabaseClient,
          onSongSelected: widget.onSongSelected,
          currentlyPlayingSong: widget.currentlyPlayingSong,
          inMainLayout: true, // Flag to indicate it's in the main layout
          onBackPressed: widget.onBackPressed,
        );
      case ContentType.artist:
        if (_contentData == null) {
          return const Center(child: Text('No artist data', style: TextStyle(color: Colors.white)));
        }
        return Material(
          color: Colors.transparent,
          child: ArtistDetailsPage(
            artist: _contentData!,
            onBackPressed: widget.onBackPressed,
          ),
        );
      default:
        return Container(); // This will be replaced by the TabBarView in HomeScreen
    }
  }
}

// A controller to manage content navigation from anywhere in the app
class ContentViewController {
  static final ContentViewController _instance = ContentViewController._internal();
  factory ContentViewController() => _instance;
  ContentViewController._internal();

  final List<Function(ContentType, {Map<String, dynamic>? data})> _listeners = [];

  void addListener(Function(ContentType, {Map<String, dynamic>? data}) listener) {
    _listeners.add(listener);
  }

  void removeListener(Function(ContentType, {Map<String, dynamic>? data}) listener) {
    _listeners.remove(listener);
  }

  void navigateTo(ContentType contentType, {Map<String, dynamic>? data}) {
    for (var listener in _listeners) {
      listener(contentType, data: data);
    }
  }
}
