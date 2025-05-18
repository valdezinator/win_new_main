import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../music_player.dart';
import '../services/audio_service.dart';
import '../sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/queue_list.dart';
import '../widgets/lyrics_panel.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  final int currentIndex;
  final Map<String, dynamic>? currentSong;
  final AudioService audioService;
  final Function(Map<String, dynamic>) onSongSelected;
  final Function(int) onNavItemSelected;
  final bool showQueue;
  final Function(bool) onQueueToggle;

  const MainLayout({
    super.key,
    required this.child,
    required this.currentIndex,
    this.currentSong,
    required this.audioService,
    required this.onSongSelected,
    required this.onNavItemSelected,
    this.showQueue = false,
    required this.onQueueToggle,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  // Lyrics overlay state
  bool _showLyrics = false;
  String? _lyrics;
  Duration _lyricsCurrentPosition = Duration.zero;
  Duration _lyricsTotalDuration = Duration.zero;
  Color _lyricsAccentColor = Colors.green;

  void openLyricsPanel({
    required String? lyrics,
    required Duration currentPosition,
    required Duration totalDuration,
    required Color accentColor,
  }) {
    setState(() {
      _showLyrics = true;
      _lyrics = lyrics;
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
                          _buildNavItem(2, 'assets/icons/library_icon.svg', 'Library'),
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

          // Music Player (if a song is selected)
          if (widget.currentSong != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MusicPlayer(
                song: widget.currentSong!,
                onQueueToggle: widget.onQueueToggle,
                showQueue: widget.showQueue,
                onShowLyrics: ({
                  required Duration currentPosition,
                  required Duration totalDuration,
                  required Color accentColor,
                  String? lyrics,
                }) => openLyricsPanel(
                  lyrics: lyrics,
                  currentPosition: currentPosition,
                  totalDuration: totalDuration,
                  accentColor: accentColor,
                ),
              ),
            ),

          // Queue List (conditionally shown)
          if (widget.showQueue && widget.currentSong != null)
            Positioned(
              top: 60.0,
              right: 0,
              bottom: 80.0, // Height of the MusicPlayer
              child: QueueList(
                currentSong: widget.currentSong!,
                onClose: () => widget.onQueueToggle(false),
                onSongSelected: widget.onSongSelected,
              ),
            ),

          // Lyrics overlay (top-level)
          if (_showLyrics)
            Positioned(
              top: 0,
              right: 0,
              bottom: 80, // Height of the MusicPlayer
              width: 340,
              child: IgnorePointer(
                ignoring: !_showLyrics,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _showLyrics ? 1.0 : 0.0,
                  child: Material(
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
                              lyrics: _lyrics,
                              onClose: closeLyricsPanel,
                              currentPosition: _lyricsCurrentPosition,
                              totalDuration: _lyricsTotalDuration,
                              accentColor: _lyricsAccentColor,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: Icon(Icons.close, color: Colors.white.withOpacity(0.85)),
                              onPressed: closeLyricsPanel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
}
