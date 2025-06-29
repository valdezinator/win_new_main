import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' show Random;
import 'dart:ui';
import 'dart:async';
import 'services/audio_service.dart';
import 'services/jam_session_service.dart';
import 'services/noise_detection_service.dart';
import 'services/route_tracking_service.dart';
import 'services/ad_manager_service.dart';
import 'services/listening_time_service.dart';
import 'widgets/jam_session_indicator.dart';
import 'widgets/adaptive_features_indicator.dart';
import 'widgets/lyrics_panel.dart';
import 'widgets/ad_controls.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MusicPlayer extends StatefulWidget {
  final Map<String, dynamic> song;
  final Function(bool)? onQueueToggle;
  final bool showQueue;
  final Function({required Color accentColor, required Duration currentPosition, required Duration totalDuration, String? lyrics, String? translatedLyrics})? onShowLyrics;

  const MusicPlayer({
    super.key,
    required this.song,
    this.onQueueToggle,
    this.showQueue = false,
    this.onShowLyrics,
  });

  @override
    State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> with TickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  final JamSessionService _jamSessionService = JamSessionService();
  final NoiseDetectionService _noiseDetectionService = NoiseDetectionService();
  final RouteTrackingService _routeTrackingService = RouteTrackingService();
  final AdManagerService _adManager = AdManagerService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final ListeningTimeService _listeningTimeService = ListeningTimeService();
  
  bool isShuffleEnabled = false;
  bool isRepeatEnabled = false;
  bool isInLibrary = true;
  bool isFullScreen = false;
  double volume = 0.8;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  late AnimationController _animationController;
  bool isPlaying = false;
  FocusNode? _focusNode;
  bool _isInJamSession = false;
  
  // Track active states of adaptive features
  bool _noiseAdaptiveActive = false;
  bool _routeCacheActive = false;

  // Animation controller for full screen transition
  late AnimationController _fullScreenAnimController;

  // Full screen exit key handler
  final FocusNode _fullScreenFocusNode = FocusNode();

  // Color palette variables
  Color dominantColor = Colors.black;
  Color accentColor = Colors.green;
  bool isDarkPalette = true;

  // Timer for periodic jam session updates
  Timer? _jamSessionUpdateTimer;
  
  // Listening time tracking
  StreamSubscription? _listeningTimeSubscription;
  StreamSubscription? _adEligibilitySubscription;
  int _todayListeningMinutes = 0;
  bool _hasReached10Minutes = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    // Restore shuffle/repeat state
    _restorePlayerPreferences();
    
    // Initialize listening time service
    _initializeListeningTimeService();
    
    // Initialize ad service with the main audio player
    _adManager.initialize(_audioService.player);
    
    // Monitor adaptive features active state
    _setupAdaptiveFeaturesListeners();

    // Initialize full screen animation controller
    _fullScreenAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Set up keyboard listener for ESC key to exit full screen
    _fullScreenFocusNode.addListener(() {
      if (_fullScreenFocusNode.hasFocus) {
        // This ensures we can capture key events
        debugPrint("Full screen focus node has focus");
      }
    });

    _setupAudioPlayer();
    _updatePaletteGenerator();

    // Check jam session status and listen for changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isInJamSession = _jamSessionService.isInSession;
      if (_isInJamSession && mounted) {
        setState(() {});

        // Start periodic updates if we're the host
        if (_jamSessionService.isHost) {
          _startJamSessionUpdates();
        }
      }

      // Subscribe to jam session changes
      _jamSessionService.sessionStream.listen((session) {
        if (mounted) {
          setState(() {
            _isInJamSession = session != null;
          });
            // If in a session and not the host, sync with host's playback
          if (_isInJamSession && !_jamSessionService.isHost && session != null) {
            // Sync playback with the host
            final currentSongId = session['current_song'];
            final positionMs = session['position_ms'] ?? 0;
            final isSessionPlaying = session['is_playing'] ?? false;
            final queue = session['queue'];

            if (currentSongId != null && queue != null) {
              // Find the song in the queue
              final songIndex = (queue as List).indexWhere((song) => song['id'] == currentSongId);
              if (songIndex != -1) {
                // Play the song
                final songToPlay = Map<String, dynamic>.from(queue[songIndex]);
                songToPlay['queue'] = queue;

                // Only change song if it's different from current
                if (widget.song['id'] != currentSongId) {
                  _audioService.playSong(songToPlay);

                  // Seek to position
                  if (positionMs > 0) {
                    _audioService.player.seek(Duration(milliseconds: positionMs));
                  }
                }

                // Match play state
                if (isPlaying != isSessionPlaying) {
                  if (isSessionPlaying) {
                    _audioService.play();
                  } else {
                    _audioService.pause();
                  }
                }
              }
            }
          }
        }
      });
    });
  }

  // Initialize listening time service and set up listeners
  Future<void> _initializeListeningTimeService() async {
    await _listeningTimeService.initialize();
    
    // Listen to listening time updates
    _listeningTimeSubscription = _listeningTimeService.listeningTimeStream.listen((minutes) {
      if (mounted) {
        setState(() {
          _todayListeningMinutes = minutes;
        });
      }
    });
    
    // Listen to ad eligibility changes
    _adEligibilitySubscription = _listeningTimeService.adEligibilityStream.listen((eligible) {
      if (mounted) {
        setState(() {
          _hasReached10Minutes = eligible;
        });
      }
    });
    
    // Get initial values
    _todayListeningMinutes = _listeningTimeService.todayListeningMinutes;
    _hasReached10Minutes = _listeningTimeService.hasReached10Minutes;
  }

  // Set up listeners for adaptive features active state
  void _setupAdaptiveFeaturesListeners() {
    // Add listeners for noise detection service
    _noiseDetectionService.addListener(() {
      if (mounted) {
        setState(() {
          _noiseAdaptiveActive = _noiseDetectionService.isActive;
        });
      }
    });
    
    // Add listeners for route tracking service
    _routeTrackingService.addListener(() {
      if (mounted) {
        setState(() {
          _routeCacheActive = _routeTrackingService.isActive;
        });
      }
    });
    
    // Get initial state
    _noiseAdaptiveActive = _noiseDetectionService.isActive;
    _routeCacheActive = _routeTrackingService.isActive;
  }

  Future<void> _setupAudioPlayer() async {
    // Listen to position changes
    _audioService.player.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          currentPosition = position;
        });
        // Update lyrics panel if it's shown
        if (widget.onShowLyrics != null && widget.song['song_lyrics'] != null) {
          widget.onShowLyrics!(                  accentColor: accentColor,
                  currentPosition: position,
                  totalDuration: totalDuration,
                  lyrics: widget.song['song_lyrics'],
                  translatedLyrics: widget.song['lyrics_in_eng'],
                );
        }
      }
    });

    // Listen to duration changes
    _audioService.player.durationStream.listen((duration) {
      if (duration != null && mounted) {
        setState(() => totalDuration = duration);
      }
    });

    // Listen to player state changes
    _audioService.player.playerStateStream.listen((playerState) {
      if (mounted) {
        // setState(() { // Original setState call
        //   isPlaying = playerState.playing;
        //   if (playerState.processingState == ProcessingState.completed) {
        //     currentPosition = Duration.zero; // This was potentially problematic if completion logic relies on old position
        //     _handleSongCompletion();
        //   }
        // });
        // Revised logic to handle completion more cleanly
        final wasPlaying = isPlaying;
        final newIsPlaying = playerState.playing;
        if (wasPlaying != newIsPlaying) {
          setState(() {
            isPlaying = newIsPlaying;
          });
        }
        if (playerState.processingState == ProcessingState.completed) {
          // Don't reset currentPosition to zero here immediately,
          // let the new song load and update its duration/position.
          // If it's the same song repeating, seek(Duration.zero) will handle it.
          _handleSongCompletion();
        }
      }
    });

    // Listen to playing state changes
    _audioService.isPlayingStream.listen((playing) {
      if (mounted) {
        setState(() => isPlaying = playing);
      }
    });

    // Set initial volume
    await _audioService.player.setVolume(volume);
  }

  Future<void> _updatePaletteGenerator() async {
    if (widget.song['image_url'] == null) return;

    try {
      final imageProvider = NetworkImage(widget.song['image_url']);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(imageProvider);

      if (mounted) {
        setState(() {
          // Extract dominant color
          dominantColor = paletteGenerator.dominantColor?.color ?? Colors.black;

          // Determine if the palette is dark
          final luminance = paletteGenerator.dominantColor?.color.computeLuminance() ?? 0;
          isDarkPalette = luminance < 0.5;

          // Extract vibrant or accent color for highlights
          accentColor = paletteGenerator.vibrantColor?.color ??
                       paletteGenerator.lightVibrantColor?.color ??
                       Colors.green;
        });
      }
    } catch (e) {
      // Fallback if image loading fails
      setState(() {
        dominantColor = Colors.black;
        accentColor = Colors.green;
        isDarkPalette = true;
      });
    }
  }
  Future<void> _fetchLyrics(String songId) async {
    try {
      final response = await Supabase.instance.client
          .from('songs_2')
          .select('song_lyrics, lyrics_in_eng')
          .eq('id', songId)
          .single();
      
      if (response != null && mounted) {
        setState(() {
          widget.song['song_lyrics'] = response['song_lyrics'];
          widget.song['lyrics_in_eng'] = response['lyrics_in_eng'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching lyrics: $e');
    }
  }

  void _handleSongCompletion() {
    if (isRepeatEnabled) {
      // Replay the current song
      final songToReplay = Map<String, dynamic>.from(widget.song);
      // Ensure lyrics data is preserved - commented out
      // songToReplay['song_lyrics'] = widget.song['song_lyrics'];
      _audioService.playSong(songToReplay);
    } else if (isShuffleEnabled) {
      // Play a random song from the queue
      final List<Map<String, dynamic>> currentQueue = List<Map<String, dynamic>>.from(widget.song['queue'] ?? []);
      if (currentQueue.isEmpty) return;
      
      final random = Random();
      final songToPlay = currentQueue[random.nextInt(currentQueue.length)];
      _audioService.playSong(songToPlay);
    } else {
      // Play the next song
      _audioService.playNext();
    }
  }

  void toggleShuffle() {
    setState(() {
      isShuffleEnabled = !isShuffleEnabled;
      if (isShuffleEnabled) {
        isRepeatEnabled = false;
      }
    });
    _savePlayerPreferences();
  }

  void toggleRepeat() {
    setState(() {
      isRepeatEnabled = !isRepeatEnabled;
      if (isRepeatEnabled) {
        isShuffleEnabled = false;
      }
    });
    _savePlayerPreferences();
  }
  void toggleLyrics() {
    setState(() {
      // showLyrics = !showLyrics;
      if (widget.song['song_lyrics'] == null && widget.song['id'] != null) {
        _fetchLyrics(widget.song['id'].toString());
      }
    });
  }

  void _handlePlayPause() {
    _audioService.togglePlayPause();

    // Update jam session if host
    if (_isInJamSession && _jamSessionService.isHost) {
      _updateJamSessionPlayback();
    }

    // Handle listening time tracking
    if (isPlaying) {
      // Music is being paused - end listening session
      _listeningTimeService.endSession();
      
      _analyticsService.logSongPlayback(
        songId: widget.song['id'].toString(),
        songTitle: widget.song['title'],
        artistName: widget.song['artist'],
        albumName: widget.song['album'],
        eventType: 'song_pause',
      );
    } else {
      // Music is being played - start listening session
      _listeningTimeService.startSession();
      
      _analyticsService.logSongPlayback(
        songId: widget.song['id'].toString(),
        songTitle: widget.song['title'],
        artistName: widget.song['artist'],
        albumName: widget.song['album'],
        eventType: 'song_play',
      );
    }
  }

  void _handleNext() {
    _audioService.playNext();

    // Update jam session if host
    if (_isInJamSession && _jamSessionService.isHost) {
      _updateJamSessionPlayback();
    }
  }

  void _handlePrevious() {
    _audioService.playPrevious();

    // Update jam session if host
    if (_isInJamSession && _jamSessionService.isHost) {
      _updateJamSessionPlayback();
    }
  }

  // Method to update jam session playback state
  void _updateJamSessionPlayback() {
    if (!_jamSessionService.isHost || !_isInJamSession) return;

    _jamSessionService.updateSessionPlayback(
      widget.song,
      currentPosition.inMilliseconds,
      isPlaying
    );
  }

  // Start periodic jam session updates
  void _startJamSessionUpdates() {
    _jamSessionUpdateTimer?.cancel();

    if (_isInJamSession && _jamSessionService.isHost) {
      // Update every 5 seconds to keep participants in sync
      _jamSessionUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _updateJamSessionPlayback();
      });
    }
  }

  // Stop periodic updates
  void _stopJamSessionUpdates() {
    _jamSessionUpdateTimer?.cancel();
    _jamSessionUpdateTimer = null;
  }

  @override
  void didUpdateWidget(MusicPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update when song details change
    if (widget.song['id'] != oldWidget.song['id']) {
      // Reset position and duration when a new song is selected
      setState(() {
        currentPosition = Duration.zero;
        totalDuration = Duration.zero;
      });
      _audioService.playSong(widget.song);
      
      // Fetch lyrics for the new song
      if (widget.song['id'] != null) {
        _fetchLyrics(widget.song['id'].toString());
      }

      // Update the color palette for the new song
      _updatePaletteGenerator();
    }
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    _fullScreenFocusNode.dispose();
    _animationController.dispose();
    _fullScreenAnimController.dispose();
    _stopJamSessionUpdates(); // Ensure timer is cancelled
    _adManager.dispose(); // Dispose ad manager
    
    // Clean up listening time subscriptions
    _listeningTimeSubscription?.cancel();
    _adEligibilitySubscription?.cancel();
    
    // End any active listening session
    _listeningTimeService.endSession();
    
    super.dispose();
  }

  // Toggle full screen music player overlay
  void _toggleFullScreen() {
    setState(() {
      isFullScreen = !isFullScreen;
    });

    if (isFullScreen) {
      _fullScreenAnimController.forward();
      // Request focus to capture keyboard events
      _fullScreenFocusNode.requestFocus();
    } else {
      _fullScreenAnimController.reverse();
      _fullScreenFocusNode.unfocus();
    }
  }

  // Build the full screen music player overlay
  Widget _buildFullScreenPlayer() {
    return AnimatedOpacity(
      opacity: isFullScreen ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Visibility(
        visible: isFullScreen,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          color: Colors.black,
          child: Stack(
            children: [
              // Background with blurred album art
              Positioned.fill(
                child: widget.song['image_url'] != null
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Image.network(
                        widget.song['image_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: dominantColor,
                        ),
                      ),
                    )
                  : Container(color: dominantColor),
              ),

              // Darkening overlay
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.7),
                ),
              ),

              // Main content: Player (left) + Lyrics (right)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // LEFT: Player UI
                    Expanded(
                      flex: 10,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 420,
                            minWidth: 260,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Album art
                              Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    widget.song['image_url'] ?? '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.music_note, color: Colors.white, size: 80),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Song title
                              Text(
                                widget.song['title'] ?? 'Unknown',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w300,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              // Artist name
                              Text(
                                widget.song['artist'] ?? 'Unknown Artist',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w300,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              // Progress bar
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 340),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _formatDuration(currentPosition),
                                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: SliderTheme(
                                              data: SliderThemeData(
                                                trackHeight: 2,
                                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                                                activeTrackColor: accentColor,
                                                inactiveTrackColor: Colors.grey[800],
                                                thumbColor: accentColor,
                                              ),
                                              child: Slider(
                                                value: _safeSliderValue(currentPosition.inSeconds.toDouble(), totalDuration.inSeconds > 0 ? totalDuration.inSeconds.toDouble() : 1.0),
                                                max: totalDuration.inSeconds > 0 ? totalDuration.inSeconds.toDouble() : 1.0,
                                                onChanged: (value) {
                                                  _audioService.player.seek(Duration(seconds: value.toInt()));
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatDuration(totalDuration),
                                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              // Playback controls
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildHoverButton(
                                    child: Icon(
                                      Icons.shuffle,
                                      color: isShuffleEnabled ? accentColor : Colors.white.withOpacity(0.7),
                                      size: 22,
                                    ),
                                    onPressed: toggleShuffle,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  const SizedBox(width: 20),
                                  _buildHoverButton(
                                    icon: Icons.skip_previous,
                                    color: Colors.white,
                                    onPressed: _handlePrevious,
                                    size: 30,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  const SizedBox(width: 20),
                                  _buildHoverButton(
                                    icon: isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_filled,
                                    color: Colors.white,
                                    onPressed: _handlePlayPause,
                                    size: 48,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  const SizedBox(width: 20),
                                  _buildHoverButton(
                                    icon: Icons.skip_next,
                                    color: Colors.white,
                                    onPressed: _handleNext,
                                    size: 30,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  const SizedBox(width: 20),
                                  _buildHoverButton(
                                    child: Icon(
                                      Icons.repeat,
                                      color: isRepeatEnabled ? accentColor : Colors.white.withOpacity(0.7),
                                      size: 22,
                                    ),
                                    onPressed: toggleRepeat,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 28),
                    // RIGHT: Lyrics Panel
                    Expanded(
                      flex: 6,
                      child: Container(
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
                          child: LyricsPanel(
                            lyrics: widget.song['song_lyrics'],
                            translatedLyrics: widget.song['lyrics_in_eng'],
                            onClose: () {}, // No close button in full screen
                            currentPosition: currentPosition,
                            totalDuration: totalDuration,
                            accentColor: accentColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Exit button
              Positioned(
                top: 20,
                right: 20,
                child: _buildHoverButton(
                  icon: Icons.close,
                  color: Colors.white,
                  onPressed: _toggleFullScreen,
                  size: 32,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method for SVG icons (kept for reference but not used in the updated UI)
  // Widget _buildSvgIcon(String filePath, {Color? color, double size = 24}) {
  //   return SvgPicture.asset(
  //     filePath,
  //     width: size,
  //     height: size,
  //     colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
  //   );
  // }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }
  @override
  Widget build(BuildContext context) {
    // Show visual indicators for adaptive features
    final showAdaptiveIndicators = _noiseAdaptiveActive || _routeCacheActive;
    return KeyboardListener(
      focusNode: _fullScreenFocusNode,
      onKeyEvent: (KeyEvent event) {
        // Only handle KeyDownEvent to avoid duplicate events
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape && isFullScreen) {
            _toggleFullScreen();
          }
        }
        // Always mark the event as handled to prevent it from propagating
        return;
      },
      child: Stack(
        children: [
          // Base player UI
          // Listen to ad state to show appropriate UI
          StreamBuilder<bool>(
            stream: Stream.periodic(const Duration(milliseconds: 100)).map((_) => _adManager.isAdPlaying),
            initialData: _adManager.isAdPlaying,
            builder: (context, snapshot) {
              final isAdPlaying = snapshot.data ?? false;
              
              // Always show the player container to maintain layout, but change content
              return Focus(
                focusNode: _focusNode,
                autofocus: false,
                onKeyEvent: (node, event) {
                  // Only handle KeyDownEvent to avoid duplicate events
                  if (event is KeyDownEvent) {
                    // Add your key handling logic here
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    height: 80,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF080A0D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: isAdPlaying
                        ? SizedBox(
                            height: 80, // Match the parent container height
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Advertisement',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14, // Reduced font size
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4), // Reduced spacing
                                  Expanded(
                                    child: AdControls(),
                                  ),
                                  // Fallback error message area (shown if ad fails)
                                  StreamBuilder<PlayerState>(
                                    stream: _audioService.player.playerStateStream,
                                    builder: (context, snapshot) {
                                      final state = snapshot.data;
                                      if (state != null && state.processingState == ProcessingState.idle) {
                                        return Text(
                                          'Ad failed to load. Resuming music...',
                                          style: TextStyle(color: Colors.red[200], fontSize: 10), // Reduced font size
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Row( // Show normal player UI when no ad
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Left section - Song Info
                              Container(
                                width: 220,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    // Album art
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        widget.song['image_url'] ?? '',
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                          Container(
                                            width: 56,
                                            height: 56,
                                            color: Colors.grey[800],
                                            child: const Icon(Icons.music_note, color: Colors.white, size: 24),
                                          ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Song title and artist
                                    Flexible(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          // Song title
                                          SizedBox(
                                            height: 20,
                                            width: 140, // Reduced from 200 to match layout
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final text = widget.song['title'] ?? 'Unknown';
                                                final textPainter = TextPainter(
                                                  text: TextSpan(
                                                    text: text,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  maxLines: 1,
                                                  textDirection: TextDirection.ltr,
                                                )..layout(maxWidth: double.infinity);

                                                if (textPainter.width > constraints.maxWidth) {
                                                  return Marquee(
                                                    text: text,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    scrollAxis: Axis.horizontal,
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    blankSpace: 20.0,
                                                    velocity: 30.0,
                                                    pauseAfterRound: const Duration(seconds: 1),
                                                    startPadding: 10.0,
                                                    accelerationDuration: const Duration(seconds: 1),
                                                    accelerationCurve: Curves.linear,
                                                    decelerationDuration: const Duration(milliseconds: 500),
                                                    decelerationCurve: Curves.easeOut,
                                                  );
                                                }
                                                return Text(
                                                  text,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                );
                                              },
                                            ),
                                          ),

                                          // Artist name
                                          SizedBox(
                                            height: 16,
                                            width: 140, // Reduced from 200 to match layout
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final text = widget.song['artist'] ?? 'Unknown Artist';
                                                final textPainter = TextPainter(
                                                  text: TextSpan(
                                                    text: text,
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.7),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  maxLines: 1,
                                                  textDirection: TextDirection.ltr,
                                                )..layout(maxWidth: double.infinity);

                                                if (textPainter.width > constraints.maxWidth) {
                                                  return Marquee(
                                                    text: text,
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.7),
                                                      fontSize: 12,
                                                    ),
                                                    scrollAxis: Axis.horizontal,
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    blankSpace: 20.0,
                                                    velocity: 30.0,
                                                    pauseAfterRound: const Duration(seconds: 1),
                                                    startPadding: 10.0,
                                                    accelerationDuration: const Duration(seconds: 1),
                                                    accelerationCurve: Curves.linear,
                                                    decelerationDuration: const Duration(milliseconds: 500),
                                                    decelerationCurve: Curves.easeOut,
                                                  );
                                                }
                                                return Text(
                                                  text,
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.7),
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Center section - Playback Controls and Progress Bar
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Progress bar with duration on either side
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center, // Center the entire row
                                      children: [
                                        Flexible(
                                          child: Container(
                                            constraints: const BoxConstraints(maxWidth: 400), // Constrain maximum width
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                // Current position
                                                Text(
                                                  _formatDuration(currentPosition),
                                                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
                                                ),
                                                const SizedBox(width: 8),

                                                // Progress slider
                                                Expanded(
                                                  child: SliderTheme(
                                                    data: SliderThemeData(
                                                      trackHeight: 2,
                                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                                                      activeTrackColor: accentColor,
                                                      inactiveTrackColor: Colors.grey[800],
                                                      thumbColor: accentColor,
                                                    ),
                                                    child: Slider(
                                                      value: _safeSliderValue(currentPosition.inSeconds.toDouble(), totalDuration.inSeconds > 0 ? totalDuration.inSeconds.toDouble() : 1.0),
                                                      max: totalDuration.inSeconds > 0 ? totalDuration.inSeconds.toDouble() : 1.0,
                                                      onChanged: (value) {
                                                        _audioService.player.seek(Duration(seconds: value.toInt()));
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // Total duration
                                                Text(
                                                  _formatDuration(totalDuration),
                                                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Playback controls
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Shuffle button
                                        _buildHoverButton(
                                          child: Icon(
                                            Icons.shuffle,
                                            color: isShuffleEnabled ? accentColor : Colors.white.withOpacity(0.7),
                                            size: 16,
                                          ),
                                          onPressed: toggleShuffle,
                                        ),
                                        const SizedBox(width: 24),

                                        // Previous button
                                        _buildHoverButton(
                                          icon: Icons.skip_previous,
                                          color: Colors.white,
                                          onPressed: _handlePrevious,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 16),

                                        // Play/Pause button
                                        _buildHoverButton(
                                          icon: isPlaying
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_filled,
                                          color: Colors.white,
                                          onPressed: _handlePlayPause,
                                          size: 32,
                                        ),
                                        const SizedBox(width: 16),

                                        // Next button
                                        _buildHoverButton(
                                          icon: Icons.skip_next,
                                          color: Colors.white,
                                          onPressed: _handleNext,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 24),

                                        // Repeat button
                                        _buildHoverButton(
                                          child: Icon(
                                            Icons.repeat,
                                            color: isRepeatEnabled ? accentColor : Colors.white.withOpacity(0.7),
                                            size: 16,
                                          ),
                                          onPressed: toggleRepeat,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Right section - Additional Controls
                              Container(
                                width: 220,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // Queue button
                                    _buildHoverButton(
                                      child: Icon(
                                        Icons.queue_music,
                                        color: widget.showQueue ? accentColor : Colors.white.withOpacity(0.7),
                                        size: 16,
                                      ),
                                      onPressed: () => widget.onQueueToggle?.call(!widget.showQueue),
                                    ),
                                    const SizedBox(width: 12),
                                    // Lyrics button
                                    _buildHoverButton(
                                      child: Icon(
                                        Icons.format_quote,
                                        color: (widget.song['song_lyrics'] != null) ? accentColor : Colors.white.withOpacity(0.7),
                                        size: 16,
                                      ),
                                      onPressed: () {
                                        if (widget.onShowLyrics != null) {
                                          widget.onShowLyrics!(
                                            accentColor: accentColor,
                                            currentPosition: currentPosition,
                                            totalDuration: totalDuration,
                                            lyrics: widget.song['song_lyrics'],
                                            translatedLyrics: widget.song['lyrics_in_eng'],
                                          );
                                        }
                                        if (widget.song['song_lyrics'] == null && widget.song['id'] != null) {
                                          _fetchLyrics(widget.song['id'].toString());
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 12),

                                    // Volume control
                                    Icon(
                                      Icons.volume_up,
                                      color: Colors.white.withOpacity(0.7),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),

                                    // Volume slider
                                    SizedBox(
                                      width: 60,
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 2,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                                          activeTrackColor: Colors.white,
                                          inactiveTrackColor: Colors.white.withOpacity(0.3),
                                          thumbColor: Colors.white,
                                        ),
                                        child: Slider(
                                          value: volume.clamp(0.0, 1.0),
                                          onChanged: (value) {
                                            setState(() => volume = value);
                                            _audioService.player.setVolume(value);
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Full screen button
                                    _buildHoverButton(
                                      child: Icon(
                                        isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                        color: isFullScreen ? accentColor : Colors.white.withOpacity(0.7),
                                        size: 20,
                                      ),
                                      onPressed: _toggleFullScreen,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),

          // Full screen music player overlay
          if (isFullScreen) _buildFullScreenPlayer(),

          // Jam Session indicator - should be on top of everything
          if (_isInJamSession)
            JamSessionIndicator(
              isHost: _jamSessionService.isHost,
              hostName: _jamSessionService.currentSession?['host_name'] ?? 'Unknown',
            ),
        ],
      ),
    );
  }

  Widget _buildHoverButton({
    IconData? icon,
    Widget? child,
    VoidCallback? onPressed,
    Color? color,
    double size = 24,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: padding,
          child: child ?? Icon(
            icon!,
            color: color ?? Colors.grey[400],
            size: size,
          ),
        ),
      ),
    );
  }

  Future<void> _restorePlayerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isShuffleEnabled = prefs.getBool('isShuffleEnabled') ?? false;
      isRepeatEnabled = prefs.getBool('isRepeatEnabled') ?? false;
    });
  }

  void _savePlayerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isShuffleEnabled', isShuffleEnabled);
    await prefs.setBool('isRepeatEnabled', isRepeatEnabled);
  }

  // Helper for safe slider values
  double _safeSliderValue(double value, double max) {
    if (max <= 0) return 0.0;
    return value.clamp(0.0, max);
  }
}

// Custom painter for drawing the triangle pointer
class TrianglePointer extends CustomPainter {
  final Color color;

  TrianglePointer(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}