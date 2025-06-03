import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'download_service.dart';
import 'media_control_service.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  final AudioPlayer player = AudioPlayer();
  final _currentSongController = StreamController<Map<String, dynamic>>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final DownloadService _downloadService = DownloadService();
  final MediaControlService _mediaControlService = MediaControlService();

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
    _initializeMediaControls();
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

    // Listen to position changes for media controls
    player.positionStream.listen((position) {
      _updateMediaControls();
    });

    // Listen to duration changes for media controls
    player.durationStream.listen((duration) {
      _updateMediaControls();
    });
  }

  Future<void> _initializeMediaControls() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await _mediaControlService.initialize();
    }
  }

  void _updateMediaControls() {
    if (_currentSong == null) return;

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      _mediaControlService.updateMediaControls(
        title: _currentSong!['title']?.toString() ?? 'Unknown',
        artist: _currentSong!['artist']?.toString() ?? 'Unknown Artist',
        album: _currentSong!['album']?.toString() ?? 'Unknown Album',
        artworkUrl: _currentSong!['image_url']?.toString(),
        duration: player.duration ?? Duration.zero,
        position: player.position,
        isPlaying: _isPlaying,
      );
    }
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
            _updateMediaControls();
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
      final processedSong = Map<String, dynamic>.from(songData);
      final songId = processedSong['id']?.toString();
      final isDownloaded = processedSong['downloaded'] == true;

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

      AudioSource audioSource;
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
          print('Error playing downloaded file: $e');
          return;
        }
      } else {
        // Play from URL
        audioSource = AudioSource.uri(
          Uri.parse(processedSong['audio_url']),
          tag: mediaItem,
        );
      }

      // Update current song and queue
      _currentSong = processedSong;
      _currentSongController.add(processedSong);

      if (processedSong['queue'] != null) {
        _queue = List<Map<String, dynamic>>.from(processedSong['queue']);
        _currentIndex = _queue.indexWhere((s) => s['id'] == songId);
      }

      // Set the audio source and start playing
      await player.setAudioSource(audioSource);
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);
      _updateMediaControls();

      // Save the last played song
      await _saveLastPlayedSong();
    } catch (e) {
      _isPlaying = false;
      _isPlayingController.add(false);
    }
  }

  Future<void> playNext() async {
    if (_queue.isEmpty || _currentIndex >= _queue.length - 1) {
      return;
    }

    _currentIndex++;
    await playSong(_queue[_currentIndex]);
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
        _updateMediaControls();
      }
      return;
    }

    // Otherwise, go to previous song
    if (_currentIndex > 0) {
      _currentIndex--;
      await playSong(_queue[_currentIndex]);
    }
  }

  Future<void> togglePlayPause() async {
    if (player.audioSource == null) return;

    if (_isPlaying) {
      await player.pause();
      _isPlaying = false;
      _isPlayingController.add(false);
    } else {
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);
    }
    _updateMediaControls();
  }

  Future<void> seekTo(Duration position) async {
    await player.seek(position);
    _updateMediaControls();
  }

  Future<void> setVolume(double volume) async {
    _baseVolume = volume.clamp(0.0, 1.0);
    await player.setVolume(_baseVolume);
  }

  void adjustVolume(double increment) {
    if (!_adaptiveVolumeEnabled) return;
    
    final currentVolume = player.volume;
    final newVolume = currentVolume + increment;
    
    // Cap volume at 1.0
    player.setVolume(newVolume.clamp(0.0, 1.0));
  }
  
  void resetVolume() {
    player.setVolume(_baseVolume);
  }

  void setCrossfadeDuration(int? milliseconds) {
    _baseCrossfadeDuration = milliseconds;
  }
  
  void setAdaptiveVolumeEnabled(bool enabled) {
    _adaptiveVolumeEnabled = enabled;
    
    if (!enabled) {
      resetVolume();
    }
  }
  
  bool get adaptiveVolumeEnabled => _adaptiveVolumeEnabled;

  Future<void> dispose() async {
    await _saveLastPlayedSong();
    await player.dispose();
    await _currentSongController.close();
    await _isPlayingController.close();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await _mediaControlService.dispose();
    }
  }

  Future<void> play() async {
    await player.play();
    _isPlaying = true;
    _isPlayingController.add(true);
    _updateMediaControls();
  }

  Future<void> pause() async {
    await player.pause();
    _isPlaying = false;
    _isPlayingController.add(false);
    _updateMediaControls();
  }

  Future<List<Map<String, dynamic>>> getDownloadedAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloadedAlbumsJson = prefs.getString('downloaded_albums');
      if (downloadedAlbumsJson == null) {
        return [];
      }
      return List<Map<String, dynamic>>.from(json.decode(downloadedAlbumsJson));
    } catch (e) {
      print('Error getting downloaded albums: $e');
      return [];
    }
  }
}