import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'download_service.dart';
import 'ad_manager_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/recommendation_service.dart';

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
  bool _gaplessPlayback = false;
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 1500;

  // Error logging constants
  static const int _maxTempFileAge = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
  Timer? _cleanupTimer;

  String? _currentListeningSessionId;
  DateTime? _currentListeningSessionStart;

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

  // Utility to sanitize URLs
  String sanitizeUrl(String url) {
    return url.trim().replaceAll('\n', '').replaceAll('%0A', '');
  }

  Future<void> playSong(Map<String, dynamic> song, {bool restorePosition = false}) async {
    print('[AudioService] playSong called for song id: ${song['id']}');
    // Always stop any ad playback before playing a new song
    try {
      AdManagerService().stopAd();
    } catch (e) {
      print('[AudioService] Error stopping ad: $e');
    }

    // Spotify-like ad logic: check if ad is due before playing a new song
    final adManager = AdManagerService();
    if (adManager.shouldPlayAdBeforeNextSong()) {
      await adManager.playAd();
      adManager.resetAdDue();
    }

    if (song['audio_url'] == null && song['downloaded'] != true) {
      throw Exception('Cannot play song: Missing audio URL and not downloaded');
    }

    try {
      // Notify ad manager that playback is starting
      adManager.onPlaybackStarted();
      // Dispose previous song resources
      await player.stop();
      _disposeCurrentSongResources();
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
        artUri: processedSong['image_url'] != null ? Uri.parse(sanitizeUrl(processedSong['image_url'])) : null,
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
              Uri.parse(sanitizeUrl(processedSong['audio_url'])),
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
          Uri.parse(sanitizeUrl(processedSong['audio_url'])),
          tag: mediaItem,
        );
      }

      // Only restore last position if explicitly requested (e.g., on app restart)
      Duration initialPosition = Duration.zero;
      if (restorePosition) {
        final prefs = await SharedPreferences.getInstance();
        int? lastPositionMs;
        if (_currentSong != null && _currentSong!['id'] != null) {
          lastPositionMs = prefs.getInt('last_position_ms_${_currentSong!['id']}');
        }
        if (lastPositionMs != null && lastPositionMs > 0) {
          initialPosition = Duration(milliseconds: lastPositionMs);
        }
      }

      await player.setAudioSource(audioSource, initialPosition: initialPosition);
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);
      await _saveLastPlayedSong();

      // Insert listening session for recommendations
      try {
        final user = Supabase.instance.client.auth.currentUser;
        final songId = song['id']?.toString();
        if (user != null && songId != null) {
          final response = await Supabase.instance.client.from('user_listening_sessions').insert({
            'user_id': user.id,
            'song_id': songId,
            'start_time': DateTime.now().toUtc().toIso8601String(),
          }).select().single();
          _currentListeningSessionId = response['id']?.toString();
          _currentListeningSessionStart = DateTime.now().toUtc();
        }
      } catch (e) {
        print('[AudioService] Error inserting listening session: $e');
      }
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
    
    debugPrint('[AudioService] _loadLastPlayedSong called. songJson: ' + (songJson?.substring(0, songJson.length > 200 ? 200 : songJson.length) ?? 'null'));
    if (songJson != null) {
      try {
        final song = Map<String, dynamic>.from(json.decode(songJson));
        debugPrint('[AudioService] Restored song: ' + song.toString());
        
        // Use the new playSong method with restorePosition: true to restore the last position
        await playSong(song, restorePosition: true);
        
        // Don't auto-play on app restart, just load the song
        await player.pause();
        _isPlaying = false;
        _isPlayingController.add(false);
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
        await playSong(retryData, restorePosition: false);
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
    listenToPosition();
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
          await playSong(_currentSong!, restorePosition: false);
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
    await player.pause();
    AdManagerService().onPlaybackPaused();
    _isPlaying = false;
    _isPlayingController.add(false);
  }

  Future<void> stop() async {
    await player.stop();
    AdManagerService().onPlaybackPaused();
    _isPlaying = false;
    _isPlayingController.add(false);
    // Update listening session end
    await _endListeningSession();
  }

  // Call this when a song finishes
  void onSongFinished() {
    AdManagerService().onSongFinished();
    _endListeningSession();
  }
  
  // Check if a song is downloaded
  Future<bool> isSongDownloaded(String songId) async {
    return await _downloadService.isSongDownloaded(songId);
  }

  // Get all downloaded albums
  Future<List<Map<String, dynamic>>> getDownloadedAlbums() async {
    return await _downloadService.getDownloadedAlbums();
  }

  /// Set gapless playback mode
  /// just_audio supports gapless playback by default when using ConcatenatingAudioSource.
  /// This method is a placeholder for future extensibility.
  void setGaplessPlayback(bool enabled) {
    _gaplessPlayback = enabled;
    // just_audio is gapless by default with ConcatenatingAudioSource, so no-op for now.
    // If you want to disable gapless, you could implement a workaround here.
  }

  bool get gaplessPlayback => _gaplessPlayback;

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

  bool _appendedRecommendations = false; // Prevent infinite loop

  Future<void> playNext() async {
    try {
      print('[AudioService] playNext called. _queue length: ${_queue.length}, _currentIndex: ${_currentIndex}');
      if (_queue.isEmpty || _currentIndex >= _queue.length - 1) {
        // Try to append recommendations if not already done
        if (!_appendedRecommendations) {
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            final recs = await RecommendationService().getRecommendedSongs(user.id);
            if (recs.isNotEmpty) {
              _queue.addAll(recs);
              _appendedRecommendations = true;
              print('[AudioService] playNext: Appended recommended songs to queue.');
              _currentIndex++;
              final nextSongMap = _queue[_currentIndex];
              final songToPlay = {
                ...Map<String, dynamic>.from(nextSongMap),
                'queue': _queue,
              };
              await playSong(songToPlay, restorePosition: false);
              return;
            }
          }
        }
        print('[AudioService] playNext: End of queue or queue is empty. Stopping playback.');
        if (player.playing) await player.stop();
        _isPlaying = false;
        _isPlayingController.add(false);
        _appendedRecommendations = false; // Reset for next session
        return;
      }

      _currentIndex++;
      if (_currentIndex < 0 || _currentIndex >= _queue.length) {
        print('[AudioService] playNext: _currentIndex out of bounds after increment: ${_currentIndex}');
        _isPlaying = false;
        _isPlayingController.add(false);
        _appendedRecommendations = false;
        return;
      }
      final nextSongMap = _queue[_currentIndex];
      if (nextSongMap == null) {
        print('[AudioService] playNext: nextSongMap is null at index ${_currentIndex}');
        _isPlaying = false;
        _isPlayingController.add(false);
        _appendedRecommendations = false;
        return;
      }
      final songToPlay = {
        ...Map<String, dynamic>.from(nextSongMap),
        'queue': _queue,
      };

      print('[AudioService] playNext: Playing song at index ${_currentIndex} with id: ${songToPlay['id']}');
      await playSong(songToPlay, restorePosition: false);
    } catch (e, stack) {
      print('[AudioService] playNext: Exception: ${e.toString()}');
      print(stack);
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
        await playSong(songToPlay, restorePosition: false);
      } else {
        await player.seek(Duration.zero);
      }
    } catch (e) {
      _handlePlaybackError(error: e);
    }
  }

  // Save position periodically
  void listenToPosition() {
    player.positionStream.listen((position) async {
      if (_currentSong != null && _currentSong!['id'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_position_ms_${_currentSong!['id']}', position.inMilliseconds);
      }
    });
  }

  // Dispose any listeners, timers, or resources from the previous song
  void _disposeCurrentSongResources() {
    // Cancel error reset timer if active
    _errorResetTimer?.cancel();
    _errorResetTimer = null;
    // Cancel cleanup timer if active
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    // Optionally, reset per-song state
    // (If you add per-song subscriptions or listeners, cancel them here)
  }

  // When playing a queue, ensure ConcatenatingAudioSource is used for gapless playback
  Future<void> playQueue(List<Map<String, dynamic>> queue, {int startIndex = 0}) async {
    _queue = queue;
    _currentIndex = startIndex;
    if (_queue.isEmpty) return;
    final sources = _queue.map((song) {
      final mediaItem = MediaItem(
        id: song['id']?.toString() ?? '',
        title: song['title']?.toString() ?? 'Unknown',
        artist: song['artist']?.toString() ?? 'Unknown Artist',
        duration: song['duration'] != null
            ? Duration(seconds: song['duration'] is int
                ? song['duration']
                : int.tryParse(song['duration'].toString()) ?? 0)
            : null,
        artUri: song['image_url'] != null ? Uri.parse(sanitizeUrl(song['image_url'])) : null,
      );
      return AudioSource.uri(
        Uri.parse(sanitizeUrl(song['audio_url'])),
        tag: mediaItem,
      );
    }).toList();
    final playlist = ConcatenatingAudioSource(children: sources);
    AudioSource finalSource = playlist;
    // Crossfade is not supported in the current just_audio version.
    // No crossfade can be set on the player.
    await player.setAudioSource(finalSource, initialIndex: startIndex);
    await player.play();
    _isPlaying = true;
    _isPlayingController.add(true);
  }

  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDurationMs => _crossfadeDurationMs;

  Future<void> _endListeningSession() async {
    if (_currentListeningSessionId != null && _currentListeningSessionStart != null) {
      final endTime = DateTime.now().toUtc();
      final duration = endTime.difference(_currentListeningSessionStart!).inMinutes;
      try {
        await Supabase.instance.client.from('user_listening_sessions').update({
          'end_time': endTime.toIso8601String(),
          'duration_minutes': duration,
        }).eq('id', _currentListeningSessionId!);
      } catch (e) {
        print('[AudioService] Error updating listening session: $e');
      }
      _currentListeningSessionId = null;
      _currentListeningSessionStart = null;
    }
  }
}