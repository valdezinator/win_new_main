import 'package:flutter/material.dart';
import 'package:flutter/services.dart';  // Add this import
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'dart:math';
import 'dart:ui'; // Add this import
import 'services/audio_service.dart';

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
        setState(() {
          isPlaying = playerState.playing;
          if (playerState.processingState == ProcessingState.completed) {
            currentPosition = Duration.zero;
          }
        });
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
      // Placeholder for future palette functionality
    } catch (e) {
      // Fallback if image loading fails
    }
  }

  void _handleSongCompletion() {
    if (isRepeatEnabled) {
      _audioService.player.seek(Duration.zero);
      _audioService.player.play();
    } else if (isShuffleEnabled) {
      _playRandomSong();
    } else {
      _playNextSong();
    }
  }

  void _playRandomSong() {
    final queue = List<Map<String, dynamic>>.from(widget.song['queue'] ?? []);
    if (queue.isEmpty) return;

    final random = Random();
    final currentIndex = queue.indexWhere((song) => song['id'] == widget.song['id']);
    int nextIndex;
    
    do {
      nextIndex = random.nextInt(queue.length);
    } while (nextIndex == currentIndex && queue.length > 1);

    widget.song['onSongSelected']?.call(queue[nextIndex]);
  }

  void _playNextSong() {
    final queue = List<Map<String, dynamic>>.from(widget.song['queue'] ?? []);
    if (queue.isEmpty) return;

    final currentIndex = queue.indexWhere((song) => song['id'] == widget.song['id']);
    if (currentIndex < queue.length - 1) {
      final nextSong = queue[currentIndex + 1];
      // Preserve the queue in the next song
      nextSong['queue'] = queue;
      _audioService.playSong(nextSong);
    }
  }

  void _playPreviousSong() {
    final queue = List<Map<String, dynamic>>.from(widget.song['queue'] ?? []);
    if (queue.isEmpty) return;

    final currentIndex = queue.indexWhere((song) => song['id'] == widget.song['id']);
    if (currentIndex > 0) {
      final previousSong = queue[currentIndex - 1];
      // Preserve the queue in the previous song
      previousSong['queue'] = queue;
      _audioService.playSong(previousSong);
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
  }

  void _handleNext() {
    _playNextSong();
  }

  void _handlePrevious() {
    _playPreviousSong();
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
    }
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    _animationController.dispose();
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
              height: 80, // Reduced from 90
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 2), // Reduced bottom margin from 4 to 2
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(12),
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
                  // First Column - Song Info
                  Container(
                    width: 220,
                    padding: const EdgeInsets.all(12),
                    child: IntrinsicWidth(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                widget.song['image_url'] ?? '',
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 80,
                                    height: 80,
                                    color: Colors.grey[800],
                                    child: const Icon(Icons.music_note, color: Colors.white, size: 36),
                                  ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 20,
                                    width: 180,
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
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 16,
                                    width: 180,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final text = widget.song['artist'] ?? 'Unknown Artist';
                                        final textPainter = TextPainter(
                                          text: TextSpan(
                                            text: text,
                                            style: TextStyle(
                                              color: Colors.grey[400],
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
                                              color: Colors.grey[400],
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
                                            color: Colors.grey[400],
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
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Second Column - Progress Bar and Controls
                  Container(
                    width: 340,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Progress Bar
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                _formatDuration(currentPosition),
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                    activeTrackColor: const Color.fromARGB(255, 26, 107, 37),
                                    inactiveTrackColor: Colors.grey[800],
                                    thumbColor: const Color.fromARGB(255, 26, 107, 37),
                                    overlayColor: Colors.white.withOpacity(0.2),
                                  ),
                                  child: Slider(
                                    value: currentPosition.inSeconds.toDouble(),
                                    max: totalDuration.inSeconds.toDouble(),
                                    onChanged: (value) {
                                      _audioService.player.seek(Duration(seconds: value.toInt()));
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                _formatDuration(totalDuration),
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        // Playback Controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildHoverButton(
                              child: _buildSvgIcon(
                                'assets/icons/shuffle.svg',
                                color: isShuffleEnabled ? const Color.fromARGB(255, 54, 150, 67) : Colors.grey[400],
                              ),
                              onPressed: toggleShuffle,
                            ),
                            const SizedBox(width: 10),
                            _buildHoverButton(
                              icon: Icons.skip_previous,
                              onPressed: _handlePrevious,
                            ),
                            const SizedBox(width: 10),
                            _buildHoverButton(
                              icon: isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                              onPressed: _handlePlayPause,
                              size: 36,
                            ),
                            const SizedBox(width: 10),
                            _buildHoverButton(
                              icon: Icons.skip_next,
                              onPressed: _handleNext,
                            ),
                            const SizedBox(width: 10),
                            _buildHoverButton(
                              child: _buildSvgIcon(
                                'assets/icons/repeat.svg',
                                color: isRepeatEnabled ? Colors.white : Colors.grey[400],
                              ),
                              onPressed: toggleRepeat,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Third Column - Additional Controls
                  Transform.translate(
                    offset: const Offset(-25, 0),
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildHoverButton(
                            child: _buildSvgIcon(
                              'assets/icons/queue.svg',
                              color: widget.showQueue ? Colors.green : Colors.white,
                              size: 16,
                            ),
                            onPressed: () => widget.onQueueToggle?.call(!widget.showQueue),
                          ),
                          const SizedBox(width: 6),
                          _buildHoverButton(
                            icon: Icons.headphones_rounded,
                            size: 16,
                            onPressed: () {},
                          ),
                          const SizedBox(width: 6),
                          _buildHoverButton(
                            child: Icon(
                              Icons.format_quote,
                              color: showLyrics ? Colors.green : Colors.white,
                              size: 16,
                            ),
                            onPressed: () {
                              setState(() {
                                showLyrics = !showLyrics;
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 60,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.grey[800],
                                thumbColor: Colors.white,
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
                          _buildHoverButton(
                            icon: isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            size: 20,
                            onPressed: () => setState(() => isFullScreen = !isFullScreen),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // If lyrics overlay is toggled, display it on top of the MusicPlayer UI.
        if (showLyrics) _buildLyricsOverlay(),
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