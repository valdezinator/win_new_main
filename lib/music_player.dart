import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:async';
import 'services/audio_service.dart';
import 'services/jam_session_service.dart';
import 'widgets/jam_session_indicator.dart';

class MusicPlayer extends StatefulWidget {
  final Map<String, dynamic> song;
  final Function(bool)? onQueueToggle;
  final bool showQueue;

  const MusicPlayer({
    Key? key,
    required this.song,
    this.onQueueToggle,
    this.showQueue = false,
  }) : super(key: key);

  @override
  _MusicPlayerState createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> with SingleTickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  final JamSessionService _jamSessionService = JamSessionService(); // Add JamSessionService
  bool isShuffleEnabled = false;
  bool isRepeatEnabled = false;
  bool isInLibrary = true;
  bool showLyrics = false;
  bool isFullScreen = false;
  double volume = 0.8;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  late AnimationController _animationController;
  bool isPlaying = false;
  FocusNode? _focusNode;
  bool _isInJamSession = false; // Add flag for jam session status

  // Color palette variables
  Color dominantColor = Colors.black;
  Color textColor = Colors.white;
  Color accentColor = Colors.green;
  bool isDarkPalette = true;

  // Timer for periodic jam session updates
  Timer? _jamSessionUpdateTimer;
    @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
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

  Future<void> _setupAudioPlayer() async {
    // Listen to position changes
    _audioService.player.positionStream.listen((position) {
      if (mounted) {
        setState(() => currentPosition = position);
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

          // Set text color based on palette brightness
          textColor = isDarkPalette ? Colors.white : Colors.black;

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
        textColor = Colors.white;
        accentColor = Colors.green;
        isDarkPalette = true;
      });
    }
  }

  void _handleSongCompletion() {
    if (isRepeatEnabled) {
      // Replay the current song, ensuring its queue context is maintained.
      // Create a new map to avoid modifying the original widget.song map.
      final songToReplay = Map<String, dynamic>.from(widget.song);
      // No need to call _audioService.player.seek(Duration.zero) if playSong handles it
      _audioService.playSong(songToReplay);
    } else if (isShuffleEnabled) {
      _playRandomSong();
    } else {
      _playNextSong();
    }
  }

  void _playRandomSong() {
    final List<Map<String, dynamic>> currentQueue = List<Map<String, dynamic>>.from(widget.song['queue'] ?? []);
    if (currentQueue.isEmpty) return;

    final random = Random();
    final currentIndex = currentQueue.indexWhere((s) => s['id'] == widget.song['id']);

    if (currentQueue.length == 1 && currentIndex != -1) {
        // Only one song in queue, replay if shuffle is on (and repeat is off)
        final songToReplay = Map<String, dynamic>.from(widget.song);
        _audioService.playSong(songToReplay);
        return;
    }
    if (currentQueue.length <= 1) return; // Not enough songs to shuffle to a different one

    int nextIndex;
    do {
      nextIndex = random.nextInt(currentQueue.length);
    } while (nextIndex == currentIndex); // Ensure it's a different song

    final Map<String, dynamic> nextRandomSongDetails = Map<String, dynamic>.from(currentQueue[nextIndex]);
    final Map<String, dynamic> songToPlay = {
      ...nextRandomSongDetails,
      'queue': currentQueue, // Pass the full original queue
    };
    _audioService.playSong(songToPlay);
  }

  void _playNextSong() {
    final List<Map<String, dynamic>> currentQueue = List<Map<String, dynamic>>.from(widget.song['queue'] ?? []);
    if (currentQueue.isEmpty) return;

    final currentIndex = currentQueue.indexWhere((s) => s['id'] == widget.song['id']);

    if (currentIndex != -1 && currentIndex < currentQueue.length - 1) {
      final Map<String, dynamic> nextSongDetails = Map<String, dynamic>.from(currentQueue[currentIndex + 1]);
      final Map<String, dynamic> songToPlay = {
        ...nextSongDetails,
        'queue': currentQueue, // Pass the full current queue
      };
      _audioService.playSong(songToPlay);
    }
    // If at the end of the queue and not repeating, playback will stop.
    // Playlist repeat logic (repeating the whole queue) would go here if isRepeatEnabled had a playlist mode.
  }

  void _playPreviousSong() {
    final List<Map<String, dynamic>> currentQueue = List<Map<String, dynamic>>.from(widget.song['queue'] ?? []);
    if (currentQueue.isEmpty) return;

    final currentIndex = currentQueue.indexWhere((s) => s['id'] == widget.song['id']);

    if (currentIndex > 0) { // Ensure there is a previous song
      final Map<String, dynamic> prevSongDetails = Map<String, dynamic>.from(currentQueue[currentIndex - 1]);
      final Map<String, dynamic> songToPlay = {
        ...prevSongDetails,
        'queue': currentQueue, // Pass the full current queue
      };
      _audioService.playSong(songToPlay);
    }
  }

  void toggleShuffle() {
    setState(() {
      isShuffleEnabled = !isShuffleEnabled;
      if (isShuffleEnabled) {
        isRepeatEnabled = false;
      }
    });
  }

  void toggleRepeat() {
    setState(() {
      isRepeatEnabled = !isRepeatEnabled;
      if (isRepeatEnabled) {
        isShuffleEnabled = false;
      }
    });
  }
  void _handlePlayPause() {
    _audioService.togglePlayPause();

    // Update jam session if host
    if (_isInJamSession && _jamSessionService.isHost) {
      _updateJamSessionPlayback();
    }
  }

  void _handleNext() {
    _playNextSong();

    // Update jam session if host
    if (_isInJamSession && _jamSessionService.isHost) {
      _updateJamSessionPlayback();
    }
  }

  void _handlePrevious() {
    _playPreviousSong();

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

      // Update the color palette for the new song
      _updatePaletteGenerator();
    }
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    _animationController.dispose();
    _stopJamSessionUpdates(); // Ensure timer is cancelled
    super.dispose();
  }

  // Updated helper to use full file paths for SVG icons
  Widget _buildSvgIcon(String filePath, {Color? color, double size = 24}) {
    return SvgPicture.asset(
      filePath,
      width: size,
      height: size,
      colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  // NEW: Build lyrics overlay with glassmorphism and synced highlighting
  Widget _buildLyricsOverlay() {
    if (widget.song['song_lyrics'] == null || widget.song['song_lyrics'].isEmpty) {
      return Positioned.fill(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: const Text(
              "No lyrics found",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }
    final lyricsText = widget.song['song_lyrics'];
    final words = lyricsText.split(' ');
    final totalWords = words.length;
    int highlightedIndex = 0;
    if (totalDuration.inMilliseconds > 0) {
      final progress = currentPosition.inMilliseconds / totalDuration.inMilliseconds;
      highlightedIndex = (progress * totalWords).clamp(0, totalWords - 1).toInt();
    }
    List<TextSpan> spans = [];
    for (var i = 0; i < totalWords; i++) {
      spans.add(TextSpan(
        text: words[i] + " ",
        style: TextStyle(
          color: i == highlightedIndex ? Colors.greenAccent : Colors.white,
          fontWeight: i == highlightedIndex ? FontWeight.bold : FontWeight.normal,
        ),
      ));
    }
    return Positioned.fill(
      child: GestureDetector(
        // Tap outside the lyrics box to dismiss the overlay
        onTap: () => setState(() => showLyrics = false),
        child: Container(
          alignment: Alignment.center,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: SingleChildScrollView(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(children: spans),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    // Wrap original MusicPlayer UI with Stack to support the lyrics overlay.
    return Stack(
      children: [
        Focus(
          focusNode: _focusNode,
          autofocus: false,
          onKeyEvent: (node, event) {
            // Handle repeated key events
            if (event is KeyRepeatEvent) {
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
                // Use a gradient with the dominant color
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    dominantColor.withOpacity(0.8),
                    dominantColor.withOpacity(0.2),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
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
                                width: 140,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final text = widget.song['title'] ?? 'Unknown';
                                    final textPainter = TextPainter(
                                      text: TextSpan(
                                        text: text,
                                        style: TextStyle(
                                          color: textColor,
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
                                        style: TextStyle(
                                          color: textColor,
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
                                      style: TextStyle(
                                        color: textColor,
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
                                width: 140,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final text = widget.song['artist'] ?? 'Unknown Artist';
                                    final textPainter = TextPainter(
                                      text: TextSpan(
                                        text: text,
                                        style: TextStyle(
                                          color: textColor.withOpacity(0.7),
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
                                          color: textColor.withOpacity(0.7),
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
                                        color: textColor.withOpacity(0.7),
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
                  SizedBox(
                    width: 240,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Progress bar with duration on either side
                        Row(
                          children: [
                            // Current position
                            Text(
                              _formatDuration(currentPosition),
                              style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 10),
                            ),

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
                                  value: currentPosition.inSeconds.toDouble(),
                                  max: totalDuration.inSeconds.toDouble(),
                                  onChanged: (value) {
                                    _audioService.player.seek(Duration(seconds: value.toInt()));

                                    // Update jam session if host
                                    if (_isInJamSession && _jamSessionService.isHost) {
                                      // Use a small delay to ensure seeking is complete
                                      Future.delayed(const Duration(milliseconds: 100), () {
                                        _updateJamSessionPlayback();
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),

                            // Total duration
                            Text(
                              _formatDuration(totalDuration),
                              style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 10),
                            ),
                          ],
                        ),

                        // Playback controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Shuffle button
                            _buildHoverButton(
                              child: _buildSvgIcon(
                                'assets/icons/shuffle.svg',
                                color: isShuffleEnabled ? accentColor : textColor.withOpacity(0.7),
                                size: 16,
                              ),
                              onPressed: toggleShuffle,
                            ),
                            const SizedBox(width: 24),

                            // Previous button
                            _buildHoverButton(
                              icon: Icons.skip_previous,
                              color: textColor,
                              onPressed: _handlePrevious,
                              size: 24,
                            ),
                            const SizedBox(width: 16),

                            // Play/Pause button
                            _buildHoverButton(
                              icon: isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                              color: textColor,
                              onPressed: _handlePlayPause,
                              size: 32,
                            ),
                            const SizedBox(width: 16),

                            // Next button
                            _buildHoverButton(
                              icon: Icons.skip_next,
                              color: textColor,
                              onPressed: _handleNext,
                              size: 24,
                            ),
                            const SizedBox(width: 24),

                            // Repeat button
                            _buildHoverButton(
                              child: _buildSvgIcon(
                                'assets/icons/repeat.svg',
                                color: isRepeatEnabled ? accentColor : textColor.withOpacity(0.7),
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
                          child: _buildSvgIcon(
                            'assets/icons/queue.svg',
                            color: widget.showQueue ? accentColor : textColor.withOpacity(0.7),
                            size: 16,
                          ),
                          onPressed: () => widget.onQueueToggle?.call(!widget.showQueue),
                        ),
                        const SizedBox(width: 12),

                        // Lyrics button
                        _buildHoverButton(
                          child: Icon(
                            Icons.format_quote,
                            color: showLyrics ? accentColor : textColor.withOpacity(0.7),
                            size: 16,
                          ),
                          onPressed: () {
                            setState(() {
                              showLyrics = !showLyrics;
                            });
                          },
                        ),
                        const SizedBox(width: 12),

                        // Volume slider
                        SizedBox(
                          width: 60,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                              activeTrackColor: textColor,
                              inactiveTrackColor: textColor.withOpacity(0.3),
                              thumbColor: textColor,
                            ),
                            child: Slider(
                              value: volume,
                              onChanged: (value) {
                                setState(() => volume = value);
                                _audioService.player.setVolume(value);
                              },
                            ),
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
        // If lyrics overlay is toggled, display it on top of the MusicPlayer UI.
        if (showLyrics) _buildLyricsOverlay(),
        // Jam Session indicator
        if (_isInJamSession) JamSessionIndicator(
          isHost: _jamSessionService.isHost,
          hostName: _jamSessionService.currentSession?['host_name'] ?? 'Unknown',
        ),
      ],
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
}