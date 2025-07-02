import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../music_player.dart';
import '../services/audio_service.dart';
import '../sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/queue_list.dart';
import '../widgets/lyrics_panel.dart';
import '../library_screen.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'content_view.dart'; // Adjust path if needed

class MainLayout extends StatefulWidget {
  final Widget child;
  final int currentIndex;
  final Map<String, dynamic>? currentSong;
  final AudioService audioService;
  final Function(Map<String, dynamic>) onSongSelected;
  final Function(int) onNavItemSelected;
  final bool showQueue;
  final Function(bool) onQueueToggle;
  final bool showLyrics;
  final Function({required String? lyrics, String? translatedLyrics, required Duration currentPosition, required Duration totalDuration, required Color accentColor}) openLyricsPanel;
  final VoidCallback closeLyricsPanel;
  final String? lyrics;
  final String? translatedLyrics;
  final Duration lyricsCurrentPosition;
  final Duration lyricsTotalDuration;
  final Color lyricsAccentColor;
  final Function(List<Map<String, dynamic>>)? onQueueReordered;

  const MainLayout({
    super.key,
    required this.currentIndex,
    this.currentSong,
    required this.audioService,
    required this.onSongSelected,
    required this.onNavItemSelected,
    this.showQueue = false,
    required this.onQueueToggle,
    required this.showLyrics,
    required this.openLyricsPanel,
    required this.closeLyricsPanel,
    this.lyrics,
    this.translatedLyrics,
    this.lyricsCurrentPosition = Duration.zero,
    this.lyricsTotalDuration = Duration.zero,
    this.lyricsAccentColor = Colors.green,
    this.onQueueReordered,
    required this.child,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {  // Lyrics overlay state
  bool _showLyrics = false;
  String? _lyrics;
  String? _translatedLyrics;
  Duration _lyricsCurrentPosition = Duration.zero;
  Duration _lyricsTotalDuration = Duration.zero;
  Color _lyricsAccentColor = Colors.green;
  static const double _panelWidth = 380;
  // Playlists for sidebar
  List<Map<String, dynamic>> _playlists = [];
  bool _isLoadingPlaylists = false;
  bool _playlistsExpanded = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  Future<void> _getCurrentUser() async {
    final session = Supabase.instance.client.auth.currentSession;
    final user = session?.user;
    if (user != null) {
      setState(() {
        _currentUserId = user.id;
      });
      _fetchPlaylists();
    }
  }

  Future<void> _fetchPlaylists() async {
    setState(() {
      _isLoadingPlaylists = true;
    });
    try {
      if (_currentUserId == null) {
        setState(() {
          _playlists = [];
          _isLoadingPlaylists = false;
        });
        return;
      }
      final data = await Supabase.instance.client
          .from('playlist')
          .select('id, playlist_name, image_url, user_id, description, created_at')
          .eq('user_id', _currentUserId!)
          .order('created_at', ascending: false);
      setState(() {
        _playlists = List<Map<String, dynamic>>.from(data ?? []);
        _isLoadingPlaylists = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingPlaylists = false;
      });
    }
  }

  void openLyricsPanel({
    required String? lyrics,
    String? translatedLyrics,
    required Duration currentPosition,
    required Duration totalDuration,
    required Color accentColor,
  }) {
    setState(() {
      _showLyrics = true;
      _lyrics = lyrics;
      _translatedLyrics = translatedLyrics;
      _lyricsCurrentPosition = currentPosition;
      _lyricsTotalDuration = totalDuration;
      _lyricsAccentColor = accentColor;
    });
  }

  void closeLyricsPanel() {
    setState(() {
      _showLyrics = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showAnyPanel = (widget.showQueue && widget.currentSong != null) || widget.showLyrics;
    final double rightPadding = showAnyPanel ? _panelWidth : 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      body: Stack(
        children: [
          // Main content row, shifted left when a panel is open
          AnimatedPadding(
            duration: const Duration(milliseconds: 350),
            curve: Curves.ease,
            padding: EdgeInsets.only(right: rightPadding),
            child: Row(
              children: [
                // Navigation Sidebar Container
                SizedBox(
                  width: 232, // 200 + 16 * 2 for margins
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 16, 108), // Bottom padding for music player
                    child: Material(
                      elevation: 8,
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(15),
                            bottomRight: Radius.circular(15),
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            _buildNavItem(0, 'assets/icons/home_icon.svg', 'Home'),
                            _buildNavItem(1, 'assets/icons/search_icon.svg', 'Search'),
                            _buildNavItemWithArrow(2, 'assets/icons/library_icon.svg', 'Library'),
                            if (_playlistsExpanded)
                              _isLoadingPlaylists
                                  ? const Padding(
                                      padding: EdgeInsets.only(left: 48, top: 8, bottom: 8),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        ..._playlists.map((playlist) => ListTile(
                                              leading: playlist['image_url'] != null && playlist['image_url'].toString().isNotEmpty
                                                  ? ClipRRect(
                                                      borderRadius: BorderRadius.circular(4),
                                                      child: Image.network(
                                                        playlist['image_url'],
                                                        width: 28,
                                                        height: 28,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context, error, stackTrace) => Container(
                                                          width: 28,
                                                          height: 28,
                                                          color: Colors.grey[800],
                                                          child: const Icon(Icons.music_note, color: Colors.white54, size: 16),
                                                        ),
                                                      ),
                                                    )
                                                  : const Icon(Icons.music_note, color: Colors.white54, size: 20),
                                              title: Text(
                                                playlist['playlist_name'] ?? 'Unnamed Playlist',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              onTap: () {
                                                // Navigation to playlist
                                                ContentViewController().navigateTo(ContentType.playlist, data: playlist);
                                              },
                                              contentPadding: const EdgeInsets.only(left: 56, right: 8),
                                            )),
                                        ListTile(
                                          leading: const Icon(Icons.add, color: Colors.white70, size: 20),
                                          title: const Text(
                                            'Create Playlist',
                                            style: TextStyle(color: Colors.white70, fontSize: 15),
                                          ),
                                          onTap: () async {
                                            await _showCreatePlaylistDialog(context);
                                            _fetchPlaylists(); // Refresh playlists after creation
                                          },
                                          contentPadding: const EdgeInsets.only(left: 56, right: 8),
                                        ),
                                      ],
                                    ),
                            _buildNavItem(3, 'assets/icons/profile_icon.svg', 'Profile'),
                            const Spacer(),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _handleSignOut,
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
                  child: widget.child,
                ),
              ],
            ),
          ),

          // Music Player (if a song is selected)
          if (widget.currentSong != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MusicPlayer(
                song: widget.currentSong!,
                onQueueToggle: (show) {
                  if (show) widget.closeLyricsPanel(); // Only one open at a time
                  widget.onQueueToggle(show);
                },
                showQueue: widget.showQueue,
                onShowLyrics: ({
                  required Duration currentPosition,
                  required Duration totalDuration,
                  required Color accentColor,
                  String? lyrics,
                  String? translatedLyrics,
                }) {
                  widget.openLyricsPanel(
                    lyrics: lyrics,
                    translatedLyrics: translatedLyrics,
                    currentPosition: currentPosition,
                    totalDuration: totalDuration,
                    accentColor: accentColor,
                  );
                  widget.onQueueToggle(false); // Only one open at a time
                },
              ),
            ),

            // Floating Queue Panel (Animated)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.ease,
              top: 0,
              right: (widget.showQueue && widget.currentSong != null) ? 0 : -_panelWidth,
              bottom: 80.0, // Height of the MusicPlayer
              width: _panelWidth,
              child: (widget.showQueue && widget.currentSong != null)
                  ? Material(
                      elevation: 16,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.transparent,
                      child: QueueList(
                        currentSong: widget.currentSong!,
                        onClose: () => widget.onQueueToggle(false),
                        onSongSelected: widget.onSongSelected,
                        onQueueReordered: widget.onQueueReordered,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Floating Lyrics Panel (Animated)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.ease,
              top: 0,
              right: widget.showLyrics ? 0 : -_panelWidth,
              bottom: 80.0, // Height of the MusicPlayer
              width: _panelWidth,
              child: widget.showLyrics
                  ? Material(
                      elevation: 16,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.transparent,
                      child: Container(
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF181A1F),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 24,
                              spreadRadius: 2,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: LyricsPanel(
                                lyrics: widget.lyrics,
                                translatedLyrics: widget.translatedLyrics,
                                onClose: widget.closeLyricsPanel,
                                currentPosition: widget.lyricsCurrentPosition,
                                totalDuration: widget.lyricsTotalDuration,
                                accentColor: widget.lyricsAccentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String svgPath, String text) {
    final isSelected = widget.currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => widget.onNavItemSelected(index),
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
                colorFilter: ColorFilter.mode(
                  isSelected ? Colors.white : Colors.grey,
                  BlendMode.srcIn,
                ),
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

  Widget _buildNavItemWithArrow(int index, String svgPath, String text) {
    final isSelected = widget.currentIndex == index;
    final isLibrary = text == 'Library';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          if (isLibrary) {
            setState(() {
              _playlistsExpanded = !_playlistsExpanded;
            });
          } else {
            widget.onNavItemSelected(index);
          }
        },
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
                colorFilter: ColorFilter.mode(
                  isSelected ? Colors.white : Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isLibrary)
                Icon(
                  _playlistsExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  color: Colors.white70,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
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

  // Add the create playlist dialog logic (adapted from LibraryScreen)
  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    File? _playlistCoverImage;

    Future<void> _pickImage() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null) {
        final selectedFilePath = result.files.single.path!;
        final file = File(selectedFilePath);
        if (await file.exists()) {
          _playlistCoverImage = file;
        }
      }
    }

    Future<String> _uploadImage(File image) async {
      final fileName = image.path.split('/').last;
      final response = await Supabase.instance.client.storage
          .from('playlist_covers')
          .upload(fileName, image);
      final publicUrl = Supabase.instance.client.storage
          .from('playlist_covers')
          .getPublicUrl(fileName);
      return publicUrl;
    }

    Future<void> _createPlaylist(String playlistName, String description) async {
      if (playlistName.isNotEmpty && _currentUserId != null) {
        final client = Supabase.instance.client;
        try {
          String imageUrl = '';
          if (_playlistCoverImage != null) {
            imageUrl = await _uploadImage(_playlistCoverImage!);
          }
          await client.from('playlist').insert({
            'playlist_name': playlistName,
            'description': description,
            'user_id': _currentUserId!,
            'image_url': imageUrl.isNotEmpty ? imageUrl : 'https://via.placeholder.com/300x300/1DB954/FFFFFF?text=Playlist',
            'created_at': DateTime.now().toIso8601String(),
            'type': 'user_created',
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Playlist created successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error creating playlist: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter a playlist name'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E2329),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 500,
            height: 500,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create Playlist',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                            image: _playlistCoverImage != null
                                ? DecorationImage(
                                    image: FileImage(_playlistCoverImage!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _playlistCoverImage == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate,
                                      color: Colors.white70,
                                      size: 40,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Choose photo',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: nameController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Add a name',
                                hintStyle: TextStyle(color: Colors.grey),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: descriptionController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Add an optional description',
                                hintStyle: TextStyle(color: Colors.grey),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _createPlaylist(
                            nameController.text,
                            descriptionController.text,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Create',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
