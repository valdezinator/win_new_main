import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:math' show Random;
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'services/audio_service.dart';
import 'services/jam_session_service.dart';
import 'services/noise_detection_service.dart';
import 'services/route_tracking_service.dart';
import 'services/network_service.dart';
import 'widgets/jam_session_indicator.dart';
import 'widgets/adaptive_features_indicator.dart';
import 'widgets/lyrics_panel.dart';
import 'widgets/network_aware_widget.dart' as network;
import 'package:google_fonts/google_fonts.dart';

// Add user-friendly error messages
class UserFriendlyError {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? action;

  const UserFriendlyError({
    required this.title,
    required this.message,
    this.actionLabel,
    this.action,
  });

  static UserFriendlyError fromNetworkError(NetworkException error) {
    switch (error.type) {
      case NetworkErrorType.noConnection:
        return const UserFriendlyError(
          title: 'No Internet Connection',
          message: 'Please check your internet connection and try again.',
          actionLabel: 'Retry',
        );
      case NetworkErrorType.timeout:
        return const UserFriendlyError(
          title: 'Connection Timeout',
          message: 'The request took too long to complete. Please try again.',
          actionLabel: 'Retry',
        );
      case NetworkErrorType.serverError:
        return const UserFriendlyError(
          title: 'Server Error',
          message: 'We\'re having trouble connecting to our servers. Please try again later.',
          actionLabel: 'Retry',
        );
      case NetworkErrorType.notFound:
        return const UserFriendlyError(
          title: 'Content Not Found',
          message: 'The requested content could not be found.',
        );
      default:
        return UserFriendlyError(
          title: 'Error',
          message: 'An unexpected error occurred: ${error.message}',
          actionLabel: 'Retry',
        );
    }
  }
}

// Add loading state enum
enum LoadingState {
  none,
  loadingLyrics,
  loadingAudio,
  loadingImage,
  compressingImage,
  updatingPlayback,
  syncingJamSession,
}

// Custom cache manager for album art with size limits
class AlbumArtCacheManager extends CacheManager {
  static const key = 'albumArtCache';
  static const Duration maxAge = Duration(days: 7);
  static const int maxSize = 50 * 1024 * 1024; // 50MB max cache size

  AlbumArtCacheManager() : super(Config(
    key,
    stalePeriod: maxAge,
    maxNrOfCacheObjects: 100,
    repo: JsonCacheInfoRepository(databaseName: key),
    fileService: HttpFileService(),
  ));

  Future<File> getCompressedFile(String url, {Map<String, String>? headers, String? key}) async {
    final file = await super.getSingleFile(url, headers: headers, key: key);
    // Check file size and compress if needed
    final fileSize = await file.length();
    if (fileSize > 500 * 1024) { // 500KB threshold
      final compressedFile = await _compressImage(file);
      if (compressedFile != null) {
        await file.delete();
        return compressedFile;
      }
    }
    return file;
  }

  Future<File?> _compressImage(File file) async {
    try {
      // Implement basic image compression
      final bytes = await file.readAsBytes();
      if (bytes.length > 500 * 1024) { // 500KB threshold
        // Create a temporary file for the compressed image
        final tempDir = await getTemporaryDirectory();
        final compressedFile = File('${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
        
        // Basic compression by reducing quality
        // In a real app, you might want to use a proper image compression library
        final compressedBytes = await _compressImageBytes(bytes);
        await compressedFile.writeAsBytes(compressedBytes);
        
        return compressedFile;
      }
      return null;
    } catch (e) {
      debugPrint('Error compressing image: $e');
      return null;
    }
  }

  Future<Uint8List> _compressImageBytes(Uint8List bytes) async {
    // This is a placeholder for actual image compression
    // In a real app, you would use a proper image compression library
    return bytes;
  }

  @override
  Future<void> dispose() async {
    await emptyCache();
    super.dispose();
  }
}

// Custom image widget with progressive loading
class ProgressiveAlbumArt extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool showLoadingOverlay;

  const ProgressiveAlbumArt({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.showLoadingOverlay = false,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) {
      return _buildPlaceholder();
    }

    return Stack(
      children: [
        // Low quality placeholder
        Container(
          width: width,
          height: height,
          color: Colors.grey[850],
          child: const Center(
            child: Icon(Icons.music_note, color: Colors.white, size: 24),
          ),
        ),
        // Progressive loading image
        CachedNetworkImage(
          cacheManager: AlbumArtCacheManager(),
          imageUrl: imageUrl!,
          width: width,
          height: height,
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 300),
          placeholder: (context, url) => placeholder ?? _buildPlaceholder(),
          errorWidget: (context, url, error) => errorWidget ?? _buildErrorWidget(),
          memCacheWidth: (width * MediaQuery.of(context).devicePixelRatio).round(),
          memCacheHeight: (height * MediaQuery.of(context).devicePixelRatio).round(),
        ),
        if (showLoadingOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[850],
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[850],
      child: const Icon(Icons.music_note, color: Colors.white, size: 24),
    );
  }
}

class MusicPlayer extends StatefulWidget {
  final Map<String, dynamic> song;
  final Function(bool)? onQueueToggle;
  final bool showQueue;
  final Function({required Color accentColor, required Duration currentPosition, required Duration totalDuration, String? lyrics})? onShowLyrics;

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
  final NetworkService _networkService = NetworkService();
  
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

  // Add error state tracking
  bool _hasError = false;
  String? _errorMessage;
  NetworkErrorType? _errorType;

  // Add loading state tracking
  LoadingState _loadingState = LoadingState.none;
  UserFriendlyError? _userFriendlyError;

  // Add retry count for failed requests
  int _lyricsRetryCount = 0;
  static const int _maxRetries = 3;

  // Add state management improvements
  final _stateUpdateController = StreamController<void>.broadcast();
  Timer? _stateUpdateThrottle;
  bool _isDisposed = false;

  // Add memory management
  final _imageCache = AlbumArtCacheManager();
  Timer? _cacheCleanupTimer;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
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

    _initializeState();
    _setupCacheCleanup();
  }

  void _initializeState() {
    // Throttle state updates
    _stateUpdateThrottle = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_isDisposed) {
        _stateUpdateController.add(null);
      }
    });
  }

  void _setupCacheCleanup() {
    // Clean up image cache periodically
    _cacheCleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _imageCache.emptyCache();
    });
  }

  // Optimize state updates
  void _updateState(VoidCallback update) {
    if (!_isDisposed && mounted) {
      setState(update);
    }
  }

  // Optimize audio player setup
  Future<void> _setupAudioPlayer() async {
    // Listen to position changes
    _audioService.player.positionStream
        .throttleTime(const Duration(milliseconds: 100))
        .listen((position) {
      if (!_isDisposed && mounted) {
        _updateState(() => currentPosition = position);
      }
    });

    // Listen to duration changes
    _audioService.player.durationStream
        .throttleTime(const Duration(milliseconds: 100))
        .listen((duration) {
      if (duration != null && !_isDisposed && mounted) {
        _updateState(() => totalDuration = duration);
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

    // Add error handling for audio loading
    _audioService.player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace stackTrace) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Error playing audio: $e';
            _errorType = NetworkErrorType.unknown;
            _loadingState = LoadingState.none;
          });
        }
      }
    );

    // Add loading state for audio
    _audioService.player.processingStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _loadingState = state == ProcessingState.loading || 
                          state == ProcessingState.buffering ? LoadingState.loadingAudio : LoadingState.none;
        });
      }
    });
  }

  // Optimize palette generation
  Future<void> _updatePaletteGenerator() async {
    if (widget.song['image_url'] == null) return;

    try {
      final file = await _imageCache.getCompressedFile(widget.song['image_url']);
      final imageProvider = FileImage(file);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 20, // Limit color count for better performance
      );

      if (!_isDisposed && mounted) {
        _updateState(() {
          dominantColor = paletteGenerator.dominantColor?.color ?? Colors.black;
          final luminance = paletteGenerator.dominantColor?.color.computeLuminance() ?? 0;
          isDarkPalette = luminance < 0.5;
          accentColor = paletteGenerator.vibrantColor?.color ??
                       paletteGenerator.lightVibrantColor?.color ??
                       Colors.green;
        });
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        _updateState(() {
        dominantColor = Colors.black;
        accentColor = Colors.green;
        isDarkPalette = true;
      });
      }
    }
  }

  Future<void> _fetchLyrics(String songId) async {
    if (_loadingState == LoadingState.loadingLyrics) return;
    
    _setLoadingState(LoadingState.loadingLyrics);

    try {
      final url = Uri.parse('https://yaysfbsmvtyqpbfhxstj.supabase.co/rest/v1/songs_2')
          .replace(queryParameters: {
            'id': 'eq.$songId',
            'select': 'song_lyrics',
          })
          .toString();

      final response = await _networkService.getData(
        url,
        headers: {
          'apikey': Supabase.instance.client.auth.currentSession?.accessToken ?? '',
          'Authorization': 'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken ?? ''}',
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
        cacheDuration: CacheDurations.lyrics,
        usePersistentCache: true,
      );
      
      if (response != null && response.isNotEmpty && !_isDisposed && mounted) {
        setState(() {
          widget.song['song_lyrics'] = response[0]['song_lyrics'];
          _lyricsRetryCount = 0;
        });
      } else {
        throw NetworkException(
          'No lyrics found',
          type: NetworkErrorType.notFound
        );
      }
    } on NetworkException catch (e) {
      _handleNetworkError(e);
    } catch (e) {
      _handleNetworkError(NetworkException(
        'Error fetching lyrics: $e',
        type: NetworkErrorType.unknown,
        originalError: e
      ));
    } finally {
      _setLoadingState(LoadingState.none);
    }
  }

  void _handleNetworkError(NetworkException error) {
    if (!_isDisposed && mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = error.message;
        _errorType = error.type;
        _userFriendlyError = UserFriendlyError.fromNetworkError(error);
        _loadingState = LoadingState.none;
      });

      // Retry logic for certain error types
      if (_lyricsRetryCount < _maxRetries && 
          (error.type == NetworkErrorType.timeout || 
           error.type == NetworkErrorType.serverError)) {
        _lyricsRetryCount++;
        Future.delayed(Duration(seconds: _lyricsRetryCount * 2), () {
          if (!_isDisposed && mounted && widget.song['id'] != null) {
            _fetchLyrics(widget.song['id'].toString());
          }
        });
      }
    }
  }

  void _setLoadingState(LoadingState state) {
    if (!_isDisposed && mounted) {
      setState(() {
        _loadingState = state;
        if (state == LoadingState.none) {
          _hasError = false;
          _errorMessage = null;
          _errorType = null;
          _userFriendlyError = null;
        }
      });
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
  }

  void toggleRepeat() {
    setState(() {
      isRepeatEnabled = !isRepeatEnabled;
      if (isRepeatEnabled) {
        isShuffleEnabled = false;
      }
    });
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
    _isDisposed = true;
    _stateUpdateThrottle?.cancel();
    _cacheCleanupTimer?.cancel();
    _stateUpdateController.close();
    _imageCache.dispose();
    _focusNode?.dispose();
    _fullScreenFocusNode.dispose();
    _animationController.dispose();
    _fullScreenAnimController.dispose();
    _stopJamSessionUpdates(); // Ensure timer is cancelled

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculate optimal image size based on screen size
            final maxDimension = constraints.maxWidth * 0.8;
            final imageSize = maxDimension.clamp(200.0, 400.0);

            return Container(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
          color: Colors.black,
          child: Stack(
            children: [
                  // Background with optimized blurred album art
              Positioned.fill(
                child: widget.song['image_url'] != null
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: ProgressiveAlbumArt(
                            imageUrl: widget.song['image_url'],
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                        fit: BoxFit.cover,
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

              // Content - Wrapped in SingleChildScrollView to handle overflow
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0),
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height - 80, // Leave space for padding
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Album art - Adjusted size based on screen height
                          Container(
                                width: imageSize,
                                height: imageSize,
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
                                  child: ProgressiveAlbumArt(
                                    imageUrl: widget.song['image_url'],
                                    width: imageSize,
                                    height: imageSize,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),

                          // Full screen song details
                          Text(
                            widget.song['title'] ?? 'Unknown',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 8),

                          // Artist name
                          Text(
                            widget.song['artist'] ?? 'Unknown Artist',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 40),

                          // Progress bar
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
                                            value: currentPosition.inSeconds.toDouble(),
                                            max: totalDuration.inSeconds.toDouble(),
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

                          const SizedBox(height: 25),

                          // Playback controls
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Shuffle button
                              _buildHoverButton(
                                child: Icon(
                                  Icons.shuffle,
                                  color: isShuffleEnabled ? accentColor : Colors.white.withOpacity(0.7),
                                  size: 24,
                                ),
                                onPressed: toggleShuffle,
                                padding: const EdgeInsets.all(10),
                              ),

                              const SizedBox(width: 25),

                              // Previous button
                              _buildHoverButton(
                                icon: Icons.skip_previous,
                                color: Colors.white,
                                onPressed: _handlePrevious,
                                size: 36,
                                padding: const EdgeInsets.all(10),
                              ),

                              const SizedBox(width: 25),

                              // Play/Pause button
                              _buildHoverButton(
                                icon: isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                                color: Colors.white,
                                onPressed: _handlePlayPause,
                                size: 64,
                                padding: const EdgeInsets.all(10),
                              ),

                              const SizedBox(width: 25),

                              // Next button
                              _buildHoverButton(
                                icon: Icons.skip_next,
                                color: Colors.white,
                                onPressed: _handleNext,
                                size: 36,
                                padding: const EdgeInsets.all(10),
                              ),

                              const SizedBox(width: 25),

                              // Repeat button
                              _buildHoverButton(
                                child: Icon(
                                  Icons.repeat,
                                  color: isRepeatEnabled ? accentColor : Colors.white.withOpacity(0.7),
                                  size: 24,
                                ),
                                onPressed: toggleRepeat,
                                padding: const EdgeInsets.all(10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
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
            );
          },
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
    return network.NetworkAwareWidget(
      builder: (context, isOnline) {
    // Show visual indicators for adaptive features
    final showAdaptiveIndicators = _noiseAdaptiveActive || _routeCacheActive;
        
        // Build error widget if there's an error
        Widget? errorWidget;
        if (_hasError) {
          errorWidget = Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.red.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage ?? 'An error occurred',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    if (_errorType == NetworkErrorType.noConnection)
                      const Text(
                        'Offline Mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _hasError = false;
                          _errorMessage = null;
                          _errorType = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Stack(
        children: [
          // Base player UI
          Focus(
            focusNode: _focusNode,
            autofocus: false,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                      // Left section - Song Info with loading state
                    Container(
                      width: 220,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                            // Album art with loading state
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                              child: Stack(
                                children: [
                                  widget.song['image_url'] != null
                                    ? ProgressiveAlbumArt(
                                        imageUrl: widget.song['image_url'],
                              width: 56,
                              height: 56,
                                        showLoadingOverlay: _loadingState == LoadingState.loadingImage,
                                      )
                                    : Container(
                                  width: 56,
                                  height: 56,
                                        color: Colors.grey[850],
                                  child: const Icon(Icons.music_note, color: Colors.white, size: 24),
                                ),
                                ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Song title and artist
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Text(
                                    widget.song['title'] ?? 'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.song['artist'] ?? 'Unknown Artist',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 12,
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
                    // Center section - Playback Controls and Progress Bar
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            // Progress bar with duration
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Container(
                                    constraints: const BoxConstraints(maxWidth: 400),
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
                                            value: currentPosition.inSeconds.toDouble(),
                                            max: totalDuration.inSeconds.toDouble(),
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
                          // Playback controls
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                IconButton(
                                  icon: Icon(
                                  Icons.shuffle,
                                  color: isShuffleEnabled ? accentColor : Colors.white.withOpacity(0.7),
                                    size: 20,
                                ),
                                onPressed: toggleShuffle,
                              ),
                                IconButton(
                                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 24),
                                onPressed: _handlePrevious,
                                ),
                                IconButton(
                                  icon: Icon(
                                    isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                color: Colors.white,
                                size: 32,
                              ),
                                  onPressed: _handlePlayPause,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 24),
                                onPressed: _handleNext,
                                ),
                                IconButton(
                                  icon: Icon(
                                  Icons.repeat,
                                  color: isRepeatEnabled ? accentColor : Colors.white.withOpacity(0.7),
                                    size: 20,
                                ),
                                onPressed: toggleRepeat,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                      // Right section - Volume and Full Screen
                    Container(
                        width: 120,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                            IconButton(
                              icon: Icon(
                                Icons.lyrics,
                                color: Colors.white.withOpacity(0.7),
                                size: 20,
                            ),
                            onPressed: () {
                              if (widget.onShowLyrics != null) {
                                widget.onShowLyrics!(
                                  accentColor: accentColor,
                                  currentPosition: currentPosition,
                                  totalDuration: totalDuration,
                                  lyrics: widget.song['song_lyrics'],
                                );
                              }
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.queue,
                                color: Colors.white.withOpacity(0.7),
                                size: 20,
                              ),
                              onPressed: () {
                                if (widget.onQueueToggle != null) {
                                  widget.onQueueToggle!(!widget.showQueue);
                                }
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.fullscreen,
                            color: Colors.white.withOpacity(0.7),
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
          ),
            // Full screen player overlay
          if (isFullScreen) _buildFullScreenPlayer(),
            // Adaptive features indicator
            if (showAdaptiveIndicators)
              Positioned(
                top: 0,
                right: 0,
                child: AdaptiveFeaturesIndicator(
                  noiseAdaptiveActive: _noiseAdaptiveActive,
                  routeCacheActive: _routeCacheActive,
                ),
              ),
            // Jam session indicator
          if (_isInJamSession)
              Positioned(
                top: 0,
                left: 0,
                child: JamSessionIndicator(
              isHost: _jamSessionService.isHost,
              hostName: _jamSessionService.currentSession?['host_name'] ?? 'Unknown',
                ),
              ),
            // Error widget
            if (errorWidget != null) errorWidget,
            if (_loadingState != LoadingState.none)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: _buildLoadingIndicator(),
                ),
              ),
          ],
        );
      },
      loadingWidget: const Center(
        child: CircularProgressIndicator(),
      ),
      errorWidget: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            SizedBox(height: 16),
            Text(
              'Unable to connect to the network',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
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

  // Restore adaptive features listener
  void _setupAdaptiveFeaturesListeners() {
    // Add listeners for noise detection service
    _noiseDetectionService.addListener(() {
      if (!_isDisposed && mounted) {
        _updateState(() {
          _noiseAdaptiveActive = _noiseDetectionService.isActive;
        });
      }
    });
    
    // Add listeners for route tracking service
    _routeTrackingService.addListener(() {
      if (!_isDisposed && mounted) {
        _updateState(() {
          _routeCacheActive = _routeTrackingService.isActive;
        });
      }
    });
    
    // Get initial state
    _noiseAdaptiveActive = _noiseDetectionService.isActive;
    _routeCacheActive = _routeTrackingService.isActive;
  }

  // Update loading indicator to show specific states
  Widget _buildLoadingIndicator() {
    switch (_loadingState) {
      case LoadingState.loadingLyrics:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Loading lyrics...'),
            ],
          ),
        );
      case LoadingState.loadingAudio:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Loading audio...'),
            ],
          ),
        );
      case LoadingState.loadingImage:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Loading image...'),
            ],
          ),
        );
      case LoadingState.compressingImage:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Optimizing image...'),
            ],
          ),
        );
      case LoadingState.updatingPlayback:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Updating playback...'),
            ],
          ),
        );
      case LoadingState.syncingJamSession:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Syncing with jam session...'),
            ],
          ),
        );
      case LoadingState.none:
        return const SizedBox.shrink();
    }
  }

  // Update error widget to show user-friendly messages
  Widget _buildErrorWidget() {
    if (_userFriendlyError == null) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.red.withOpacity(0.9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _userFriendlyError!.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _errorMessage = null;
                        _errorType = null;
                        _userFriendlyError = null;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _userFriendlyError!.message,
                style: const TextStyle(color: Colors.white),
              ),
              if (_userFriendlyError!.actionLabel != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _userFriendlyError!.action ?? () {
                    if (widget.song['id'] != null) {
                      _fetchLyrics(widget.song['id'].toString());
                    }
                  },
                  child: Text(
                    _userFriendlyError!.actionLabel!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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