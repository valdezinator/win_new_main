import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'download_service.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  final AudioPlayer player = AudioPlayer();
  final _currentSongController = StreamController<Map<String, dynamic>>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final DownloadService _downloadService = DownloadService();

  Map<String, dynamic>? _currentSong;
  List<Map<String, dynamic>> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  
  // For volume and crossfade control
  double _baseVolume = 0.7;
  int? _baseCrossfadeDuration;
  bool _adaptiveVolumeEnabled = false;

  Stream<Map<String, dynamic>> get currentSongStream => _currentSongController.stream;
  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  Map<String, dynamic>? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  List<Map<String, dynamic>> get queue => _queue;

  AudioService._internal() {
    _loadLastPlayedSong();
    // Setup state change handler with auto-play functionality
    player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        if (_currentIndex < _queue.length - 1) {
          // Don't stop or reset - just move to next song
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
    });
  }

  Future<void> _loadLastPlayedSong() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songJson = prefs.getString('last_played_song');

      if (songJson != null) {
        final song = Map<String, dynamic>.from(json.decode(songJson));
        _currentSong = song;
        _currentSongController.add(song);

        if (song['queue'] != null) {
          _queue = List<Map<String, dynamic>>.from(song['queue']);
          _currentIndex = _queue.indexWhere((s) => s['id'] == song['id']);
        }

        // Set up the audio source but don't start playing
        if (song['audio_url'] != null) {
          try {
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
          } catch (e) {
            // Silently fail if we can't set up the audio source
          }
        }
      }
    } catch (e) {
      // Error loading last played song, continue without it
    }
  }

  Future<void> _saveLastPlayedSong() async {
    try {
      if (_currentSong != null) {
        final prefs = await SharedPreferences.getInstance();
        // Ensure the queue in _currentSong is the most up-to-date one from the service's state
        _currentSong!['queue'] = _queue;
        await prefs.setString('last_played_song', json.encode(_currentSong));
        await prefs.setBool('was_playing', _isPlaying);
      }
    } catch (e) {
      // Error saving last played song, continue without it
    }
  }

  Future<void> playSong(Map<String, dynamic> song) async {
    // Allow playing downloaded songs even without audio_url
    if (song['audio_url'] == null && song['downloaded'] != true) {
      return;
    }

    try {
      // Extract the actual song data if it's nested
      final songData = song['songs_2'] ?? song;

      // Ensure we have all required fields
      final processedSong = {
        ...Map<String, dynamic>.from(songData),
        'id': songData['id'],
        'title': songData['title'],
        'audio_url': songData['audio_url'],
        'artist': songData['artist'],
        'image_url': songData['image_url'],
        'duration': songData['duration'],
        'song_lyrics': songData['song_lyrics'], // Include lyrics from songs_2 table
        'queue': song['queue'], // Keep the queue from the original song object
        'downloaded': song['downloaded'] ?? false, // Keep downloaded flag
        'filename': song['filename'], // Keep filename for downloaded songs
      };

      // Stop current playback first
      await player.stop();

      // Update the current song and queue state
      _currentSong = processedSong;
      _currentSongController.add(processedSong);

      if (song['queue'] != null) {
        _queue = List<Map<String, dynamic>>.from(song['queue']);
        _currentIndex = _queue.indexWhere((s) => s['id'] == song['id']);
      }

      // Check if the song is downloaded for offline playback
      final songId = processedSong['id']?.toString();
      // First check the downloaded flag, then fall back to checking the file system
      bool isDownloaded = processedSong['downloaded'] == true;
      if (!isDownloaded && songId != null) {
        isDownloaded = await _downloadService.isSongDownloaded(songId);
      }

      AudioSource? audioSource;

      // Create MediaItem with proper metadata
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
        // Play from downloaded file
        try {
          final decryptedData = await _downloadService.getDecryptedFile('song_$songId');

          // Create a temporary file to play from
          final tempDir = await getTemporaryDirectory();
          // Use platform-specific path separator
          final tempFile = File('${tempDir.path}${Platform.pathSeparator}temp_${DateTime.now().millisecondsSinceEpoch}.mp3');
          await tempFile.writeAsBytes(decryptedData);

          // Make sure the file exists before trying to play it
          if (await tempFile.exists()) {
            // Use a URI with the file scheme for Windows compatibility
            final fileUri = Uri.file(tempFile.path);
            audioSource = AudioSource.uri(
              fileUri,
              tag: mediaItem,
            );
          } else {
            throw Exception('Temporary file was not created properly');
          }
        } catch (e) {
          // Error playing downloaded file, try to fall back to streaming
          // Check if we're online before falling back to streaming
          try {
            final result = await InternetAddress.lookup('google.com');
            if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
              // Fall back to streaming if there's an error with the downloaded file
              audioSource = AudioSource.uri(
                Uri.parse(processedSong['audio_url']),
                tag: mediaItem,
              );
            } else {
              throw Exception('No internet connection and failed to play downloaded file');
            }
          } catch (_) {
            // We're offline and couldn't play the downloaded file
            throw Exception('Cannot play song: Offline and downloaded file is corrupted');
          }
        }
      } else {
        // Check if we're online before trying to stream
        try {
          final result = await InternetAddress.lookup('google.com');
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            // We're online, play from URL (streaming)
            audioSource = AudioSource.uri(
              Uri.parse(processedSong['audio_url']),
              tag: mediaItem,
            );
          } else {
            throw Exception('Cannot play song: Offline and song is not downloaded');
          }
        } catch (e) {
          throw Exception('Cannot play song: No internet connection and song is not downloaded');
        }
      }

      // Set the audio source and start playing
      await player.setAudioSource(audioSource, initialPosition: Duration.zero);

      // Start playback
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);

      // Save state after successful playback start
      await _saveLastPlayedSong();
    } catch (e) {
      _isPlaying = false;
      _isPlayingController.add(false);
      rethrow; // Re-throw to allow caller to handle
    }
  }

  // This method is no longer needed as we use the download service instead

  Future<void> togglePlayPause() async {
    try {
      if (_isPlaying) {
        await player.pause();
        _isPlaying = false;
      } else {
        if (player.audioSource != null && _currentSong != null) {
          await player.play();
          _isPlaying = true;
        } else if (_currentSong != null) {
          // If no audio source (e.g., after app restart or error), try to play _currentSong
          await playSong(_currentSong!);
        }
      }
      _isPlayingController.add(_isPlaying);
      await _saveLastPlayedSong();
    } catch (e) {
      // Error in togglePlayPause, continue
    }
  }
  Future<void> playNext() async {
    try {
      if (_queue.isEmpty) {
        if (player.playing) await player.stop();
        _isPlaying = false;
        _isPlayingController.add(false);
        return;
      }

      if (_currentIndex + 1 < _queue.length) {
        _currentIndex++;
        final nextSongMap = _queue[_currentIndex];

        // Ensure we preserve all required metadata when constructing the next song
        Map<String, dynamic> songToPlay = {
          ...Map<String, dynamic>.from(nextSongMap),
          'queue': _queue,
          'album': nextSongMap['album'] ?? _currentSong?['album'],
          'album_id': nextSongMap['album_id'] ?? _currentSong?['album_id'],
          'album_art': nextSongMap['album_art'] ?? nextSongMap['image_url'] ?? _currentSong?['album_art'],
          'artist': nextSongMap['artist'] ?? _currentSong?['artist'] ?? 'Unknown Artist',
          'duration': nextSongMap['duration'],
          'song_lyrics': nextSongMap['song_lyrics'], // Preserve lyrics data
        };

        await playSong(songToPlay);
      } else {
        if (player.playing) await player.stop();
        _isPlaying = false;
        _isPlayingController.add(false);
        // Keep _currentSong as the last played song, but update its controller
        if (_currentSong != null) {
           _currentSong!['queue'] = _queue; // Ensure queue is still attached
           _currentSongController.add(_currentSong!);
        }
      }
    } catch (e) {
      _isPlaying = false;
      _isPlayingController.add(false);
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) {
        return;
    }

    // If more than a few seconds into the current song, restart it
    if (player.position > const Duration(seconds: 3) &&
        _currentIndex >= 0 && _currentIndex < _queue.length) {
        await player.seek(Duration.zero);
        if (!_isPlaying && player.audioSource != null) {
            await player.play();
            _isPlaying = true;
            _isPlayingController.add(true);
        }
        return;
    }

    // If at the start of the song or very early, try to go to the actual previous song
    if (_currentIndex > 0) {
      _currentIndex--;
      final prevSongMap = _queue[_currentIndex];
      Map<String, dynamic> songToPlay = Map<String, dynamic>.from(prevSongMap);
      songToPlay['queue'] = _queue; // Pass the current full queue
      songToPlay['song_lyrics'] = prevSongMap['song_lyrics']; // Preserve lyrics data
      await playSong(songToPlay);
    } else {
      // At the beginning of the queue, replay the first song from the beginning
      if (_queue.isNotEmpty) {
        _currentIndex = 0;
        final firstSongMap = _queue[0];
        Map<String, dynamic> songToPlay = Map<String, dynamic>.from(firstSongMap);
        songToPlay['queue'] = _queue;
        songToPlay['song_lyrics'] = firstSongMap['song_lyrics']; // Preserve lyrics data
        await playSong(songToPlay);
        await player.seek(Duration.zero);
      }
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
      _isPlaying = false;
      _isPlayingController.add(false);
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
      // Error pausing audio, continue
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

  /// Adjust player volume relative to base volume level
  /// Used by NoiseDetectionService to increase volume in noisy environments
  /// @param increment - percentage increase (0.1 = 10% increase)
  void adjustVolume(double increment) {
    if (!_adaptiveVolumeEnabled) return;
    
    final currentVolume = player.volume;
    final newVolume = currentVolume + increment;
    
    // Cap volume at 1.0
    player.setVolume(newVolume.clamp(0.0, 1.0));
  }
  
  /// Reset volume to base level
  void resetVolume() {
    player.setVolume(_baseVolume);
  }
    /// Set crossfade duration for transitions between tracks
  /// @param milliseconds - duration of crossfade in milliseconds, null to use default
  void setCrossfadeDuration(int? milliseconds) {
    // Store the value to use when playing next songs
    _baseCrossfadeDuration = milliseconds;
    
    // In a full implementation, we would configure crossfade between tracks
    // For now, we just store the value to use when configuring playback
    // The actual crossfade implementation depends on just_audio capabilities
    // and would be applied when setting up audio sources
  }
  
  /// Enable or disable adaptive volume adjustments
  void setAdaptiveVolumeEnabled(bool enabled) {
    _adaptiveVolumeEnabled = enabled;
    
    // Reset to base volume if disabled
    if (!enabled) {
      resetVolume();
    }
  }
  
  /// Get current state of adaptive volume feature
  bool get adaptiveVolumeEnabled => _adaptiveVolumeEnabled;

  Future<void> dispose() async {
    await _saveLastPlayedSong();
    await player.dispose();
    await _currentSongController.close();
    await _isPlayingController.close();
  }
}