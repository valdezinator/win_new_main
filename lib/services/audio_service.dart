import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'download_service.dart';

/// Error types for better handling
enum PlaybackError {
  networkError,
  fileCorrupted,
  audioSourceError,
  deviceError,
  unknown
}

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  final AudioPlayer player = AudioPlayer();
  final _currentSongController = StreamController<Map<String, dynamic>>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<PlaybackError>.broadcast();
  final DownloadService _downloadService = DownloadService();

  Map<String, dynamic>? _currentSong;
  List<Map<String, dynamic>> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  
  // Error handling fields
  int _consecutiveErrors = 0;
  Timer? _errorResetTimer;
  static const int _maxConsecutiveErrors = 3;
  static const Duration _errorResetDuration = Duration(minutes: 5);
    // For volume and crossfade control
  double _baseVolume = 0.7;
  int? _baseCrossfadeDuration;
  bool _adaptiveVolumeEnabled = false;

  // Error logging constants
  static const int _maxTempFileAge = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
  Timer? _cleanupTimer;

  Stream<Map<String, dynamic>> get currentSongStream => _currentSongController.stream;
  Stream<bool> get isPlayingStream => _isPlayingController.stream;
  Stream<PlaybackError> get errorStream => _errorController.stream;

  Map<String, dynamic>? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  List<Map<String, dynamic>> get queue => _queue;

  Future<bool> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> playSong(Map<String, dynamic> song) async {
    if (song['audio_url'] == null && song['downloaded'] != true) {
      throw Exception('Cannot play song: Missing audio URL and not downloaded');
    }

    try {
      final songData = song['songs_2'] ?? song;
      final processedSong = {
        ...Map<String, dynamic>.from(songData),
        'id': songData['id'],
        'title': songData['title'],
        'audio_url': songData['audio_url'],
        'artist': songData['artist'],
        'image_url': songData['image_url'],
        'duration': songData['duration'],
        'song_lyrics': songData['song_lyrics'],
        'queue': song['queue'],
        'downloaded': song['downloaded'] ?? false,
        'filename': song['filename'],
      };

      await player.stop();
      _currentSong = processedSong;
      _currentSongController.add(processedSong);

      if (song['queue'] != null) {
        _queue = List<Map<String, dynamic>>.from(song['queue']);
        _currentIndex = _queue.indexWhere((s) => s['id'] == song['id']);
      }

      final songId = processedSong['id']?.toString();
      var isDownloaded = processedSong['downloaded'] == true;
      if (!isDownloaded && songId != null) {
        isDownloaded = await _downloadService.isSongDownloaded(songId);
      }

      late AudioSource audioSource;
      final mediaItem = MediaItem(
        id: processedSong['id']?.toString() ?? '',
        title: processedSong['title']?.toString() ?? 'Unknown',
        artist: processedSong['artist']?.toString() ?? 'Unknown Artist',
        duration: processedSong['duration'] != null
            ? Duration(seconds: processedSong['duration'] is int
                ? processedSong['duration']
                : int.tryParse(processedSong['duration'].toString()) ?? 0)
            : null,
        artUri: processedSong['image_url'] != null ? Uri.parse(processedSong['image_url']) : null,
      );

      if (isDownloaded) {
        try {
          final decryptedData = await _downloadService.getDecryptedFile('song_$songId');
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}${Platform.pathSeparator}temp_${DateTime.now().millisecondsSinceEpoch}.mp3');
          await tempFile.writeAsBytes(decryptedData);

          if (await tempFile.exists()) {
            audioSource = AudioSource.uri(
              Uri.file(tempFile.path),
              tag: mediaItem,
            );
          } else {
            throw Exception('Failed to create temporary file');
          }
        } catch (e) {
          final isOnline = await _checkInternetConnection();
          if (isOnline) {
            audioSource = AudioSource.uri(
              Uri.parse(processedSong['audio_url']),
              tag: mediaItem,
            );
          } else {
            throw Exception('Cannot play song: Offline and downloaded file is corrupted');
          }
        }
      } else {
        final isOnline = await _checkInternetConnection();
        if (!isOnline) {
          throw Exception('Cannot play song: No internet connection and not downloaded');
        }
        
        audioSource = AudioSource.uri(
          Uri.parse(processedSong['audio_url']),
          tag: mediaItem,
        );
      }

      await player.setAudioSource(audioSource, initialPosition: Duration.zero);
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);
      await _saveLastPlayedSong();
    } catch (e) {
      _isPlaying = false;
      _isPlayingController.add(false);
      _handlePlaybackError(error: e);
      rethrow;
    }
  }

  Future<void> _saveLastPlayedSong() async {
    try {
      if (_currentSong != null) {
        final prefs = await SharedPreferences.getInstance();
        _currentSong!['queue'] = _queue;
        await prefs.setString('last_played_song', json.encode(_currentSong));
        await prefs.setBool('was_playing', _isPlaying);
      }
    } catch (e) {
      // Silently fail for storage errors
      debugPrint('Error saving last played song: $e');
    }
  }

  Future<void> _loadLastPlayedSong() async {
    final prefs = await SharedPreferences.getInstance();
    final songJson = prefs.getString('last_played_song');
    
    if (songJson != null) {
      try {
        final song = Map<String, dynamic>.from(json.decode(songJson));
        _currentSong = song;
        _currentSongController.add(song);

        if (song['queue'] != null) {
          _queue = List<Map<String, dynamic>>.from(song['queue']);
          _currentIndex = _queue.indexWhere((s) => s['id'] == song['id']);
        }

        if (song['audio_url'] != null) {
          final audioSource = AudioSource.uri(
            Uri.parse(song['audio_url']),
            tag: MediaItem(
              id: song['id']?.toString() ?? '',
              title: song['title']?.toString() ?? 'Unknown',
              artist: song['artist']?.toString() ?? 'Unknown Artist',
              artUri: song['image_url'] != null ? Uri.parse(song['image_url']) : null,
            ),
          );
          await player.setAudioSource(audioSource);
          _isPlaying = false;
          _isPlayingController.add(false);
        }
      } catch (e) {
        // Error loading last played song
        _handlePlaybackError(error: e);
      }
    }
  }
  void _handlePlaybackError({Object? error}) {
    _consecutiveErrors++;
    
    // Reset error count after duration
    _errorResetTimer?.cancel();
    _errorResetTimer = Timer(_errorResetDuration, () {
      _consecutiveErrors = 0;
      // Clean up temp files periodically when resetting error count
      _cleanupTempFiles();
    });

    // Determine error type
    final PlaybackError errorType;
    if (error != null) {
      if (error.toString().contains('network') || 
         error.toString().contains('connection')) {
        errorType = PlaybackError.networkError;
      } else if (error.toString().contains('corrupted') || 
                error.toString().contains('invalid file')) {
        errorType = PlaybackError.fileCorrupted;
      } else if (error.toString().contains('audio source')) {
        errorType = PlaybackError.audioSourceError;
      } else if (error.toString().contains('device') || 
                error.toString().contains('hardware')) {
        errorType = PlaybackError.deviceError;
      } else {
        errorType = PlaybackError.unknown;
      }
    } else {
      errorType = PlaybackError.unknown;
    }

    // Notify listeners
    _errorController.add(errorType);

    // Log the error for analytics
    _logError(errorType, error);

    // Attempt recovery if we haven't had too many consecutive errors
    if (_consecutiveErrors < _maxConsecutiveErrors) {
      _attemptErrorRecovery(errorType);
    }
  }

  void _logError(PlaybackError errorType, Object? error, {Map<String, dynamic>? extraData}) {
    // Production error logging
    final errorDetails = {
      'type': errorType.toString(),
      'message': error?.toString(),
      'songId': _currentSong?['id'],
      'isDownloaded': _currentSong?['downloaded'],
      'consecutiveErrors': _consecutiveErrors,
      'timestamp': DateTime.now().toIso8601String(),
      ...?extraData,
    };
    
    // Log to console in debug, in production this should go to a logging service
    debugPrint('Audio Error: ${json.encode(errorDetails)}');
    
    // TODO: Send to analytics service
    // analyticsService.logError('audio_playback_error', errorDetails);
  }

  Future<void> _cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var file in files) {
        if (file is File && file.path.contains('temp_') && file.path.endsWith('.mp3')) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          final timestamp = int.tryParse(fileName.split('_')[1].split('.')[0]);
          if (timestamp != null && (now - timestamp) > _maxTempFileAge) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up temp files: $e');
    }
  }

  Future<void> _attemptErrorRecovery(PlaybackError errorType) async {
    if (_currentSong == null) return;

    switch (errorType) {
      case PlaybackError.networkError:
        // Try offline playback if available
        final songId = _currentSong!['id'].toString();
        if (await _downloadService.isSongDownloaded(songId)) {
          await _retrySongPlayback(true);
        }
        break;
        
      case PlaybackError.fileCorrupted:
        // Try streaming if offline file is corrupted
        if (_currentSong!['audio_url'] != null) {
          await _retrySongPlayback(false);
        }
        break;
        
      case PlaybackError.audioSourceError:
        // Try recreating audio source
        await player.stop();
        await Future.delayed(const Duration(seconds: 1));
        await _retrySongPlayback(_currentSong!['downloaded'] == true);
        break;
        
      default:
        // For unknown errors, try simple replay after delay
        await Future.delayed(const Duration(seconds: 2));
        await _retrySongPlayback(_currentSong!['downloaded'] == true);
        break;
    }
  }

  Future<void> _retrySongPlayback(bool useDownloaded) async {
    if (_currentSong != null) {
      try {
        Map<String, dynamic> retryData = Map<String, dynamic>.from(_currentSong!);
        retryData['downloaded'] = useDownloaded;
        await playSong(retryData);
      } catch (e) {
        // If retry fails, just notify via error stream
        _errorController.add(PlaybackError.unknown);
      }
    }
  }

  void _setupErrorHandling() {
    player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        if (_currentIndex < _queue.length - 1) {
          await playNext();
        } else {
          _isPlaying = false;
          _isPlayingController.add(false);
          await player.stop();
          await player.seek(Duration.zero);
        }
      }
    }, onError: (Object e, StackTrace stackTrace) {
      _isPlaying = false;
      _isPlayingController.add(false);
      _handlePlaybackError(error: e);
    });
  }

  AudioService._internal() {
    _init();
  }

  Future<void> _init() async {
    try {
      await _loadLastPlayedSong();
      _setupErrorHandling();
      _cleanupTempFiles(); // Clean up old temp files on init
    } catch (e) {
      _handlePlaybackError(error: e);
    }
  }

  Future<void> togglePlayPause() async {
    try {
      if (_isPlaying) {
        await player.pause();
        _isPlaying = false;
      } else {
        if (player.audioSource != null) {
          await player.play();
          _isPlaying = true;
        } else if (_currentSong != null) {
          await playSong(_currentSong!);
        }
      }
      _isPlayingController.add(_isPlaying);
      await _saveLastPlayedSong();
    } catch (e) {
      _handlePlaybackError(error: e);
    }
  }

  // Play the current audio
  Future<void> play() async {
    if (player.playing) return;

    try {
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);
    } catch (e) {
      _handlePlaybackError(error: e);
    }
  }

  // Pause the current audio
  Future<void> pause() async {
    if (!player.playing) return;

    try {
      await player.pause();
      _isPlaying = false;
      _isPlayingController.add(false);
    } catch (e) {
      _handlePlaybackError(error: e);
    }
  }
  
  // Check if a song is downloaded
  Future<bool> isSongDownloaded(String songId) async {
    return await _downloadService.isSongDownloaded(songId);
  }

  // Get all downloaded albums
  Future<List<Map<String, dynamic>>> getDownloadedAlbums() async {
    return await _downloadService.getDownloadedAlbums();
  }

  /// Set crossfade duration for transitions between tracks
  /// @param milliseconds - duration of crossfade in milliseconds, null to use default
  void setCrossfadeDuration(int? milliseconds) {
    _baseCrossfadeDuration = milliseconds;
    // The actual crossfade implementation depends on just_audio capabilities
    // and would be applied when setting up audio sources
  }

  void adjustVolume(double increment) {
    if (!_adaptiveVolumeEnabled) return;
    final currentVolume = player.volume;
    final newVolume = currentVolume + increment;
    player.setVolume(newVolume.clamp(0.0, 1.0));
  }
  
  void resetVolume() {
    player.setVolume(_baseVolume);
  }

  void setAdaptiveVolumeEnabled(bool enabled) {
    _adaptiveVolumeEnabled = enabled;
    if (!enabled) {
      resetVolume();
    }
  }

  bool get adaptiveVolumeEnabled => _adaptiveVolumeEnabled;

  Future<void> dispose() async {
    _errorResetTimer?.cancel();
    await _errorController.close();
    await _saveLastPlayedSong();
    await player.dispose();
    await _currentSongController.close();
    await _isPlayingController.close();
  }

  Future<void> playNext() async {
    try {
      if (_queue.isEmpty || _currentIndex >= _queue.length - 1) {
        if (player.playing) await player.stop();
        _isPlaying = false;
        _isPlayingController.add(false);
        return;
      }

      _currentIndex++;
      final nextSongMap = _queue[_currentIndex];
      final songToPlay = {
        ...Map<String, dynamic>.from(nextSongMap),
        'queue': _queue,
      };

      await playSong(songToPlay);
    } catch (e) {
      _handlePlaybackError(error: e);
    }
  }

  Future<void> playPrevious() async {
    try {
      if (player.position > const Duration(seconds: 3)) {
        await player.seek(Duration.zero);
        return;
      }

      if (_currentIndex > 0) {
        _currentIndex--;
        final prevSongMap = _queue[_currentIndex];
        final songToPlay = {
          ...Map<String, dynamic>.from(prevSongMap),
          'queue': _queue,
        };
        await playSong(songToPlay);
      } else {
        await player.seek(Duration.zero);
      }
    } catch (e) {
      _handlePlaybackError(error: e);
    }
  }
}