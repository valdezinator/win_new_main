import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  
  AudioService._internal() {
    _loadLastPlayedSong();
    
    // Setup error handler with immediate cleanup
    player.playerStateStream.listen((state) async {
      print('\n=== Player State Changed ===');
      print('Processing State: ${state.processingState}');
      print('Playing: ${state.playing}');
      
      if (state.processingState == ProcessingState.completed) {
        print('Song completed naturally, resetting player...');
        _isPlaying = false;
        _isPlayingController.add(false);
        
        // Important: Reset position immediately
        await player.seek(Duration.zero);
        await player.stop();
        
        // Try to play next song with a small delay to ensure clean state
        Future.delayed(const Duration(milliseconds: 100), () {
          playNext().then((_) {
            print('Next song started playing');
          }).catchError((e) {
            print('Error playing next song: $e');
          });
        });
      }
    }, onError: (Object e, StackTrace stackTrace) {
      print('Error in player state stream: $e');
      print('Stack trace: $stackTrace');
      _isPlaying = false;
      _isPlayingController.add(false);
    });
  }

  final AudioPlayer player = AudioPlayer();
  final _currentSongController = StreamController<Map<String, dynamic>>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  
  Map<String, dynamic>? _currentSong;
  List<Map<String, dynamic>> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;

  Stream<Map<String, dynamic>> get currentSongStream => _currentSongController.stream;
  Stream<bool> get isPlayingStream => _isPlayingController.stream;
  
  Map<String, dynamic>? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  List<Map<String, dynamic>> get queue => _queue;

  Future<void> _loadLastPlayedSong() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songJson = prefs.getString('last_played_song');
      final wasPlaying = prefs.getBool('was_playing') ?? false;
      
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
      }
    } catch (e) {
      print('Error loading last played song: $e');
    }
  }

  Future<void> _saveLastPlayedSong() async {
    try {
      if (_currentSong != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_played_song', json.encode(_currentSong));
        await prefs.setBool('was_playing', _isPlaying);
      }
    } catch (e) {
      print('Error saving last played song: $e');
    }
  }

  Future<void> playSong(Map<String, dynamic> song) async {
    print('\n=== PlaySong Called ===');
    try {
      // Stop any current playback first
      print('Stopping current playback...');
      await player.stop();
      
      // Important: Reset processing state flag
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      
      // Reset the player state
      print('Setting up new song...');
      String? audioUrl = song['audio_url']?.toString();
      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('Invalid audio URL');
      }

      // Update state
      _currentSong = Map<String, dynamic>.from(song);
      _currentSongController.add(_currentSong!);
      
      // Update queue
      if (song['queue'] != null) {
        _queue = List<Map<String, dynamic>>.from(song['queue']);
        _currentIndex = _queue.indexWhere((s) => s['id'] == song['id']);
      }

      // Create and set audio source
      final audioSource = AudioSource.uri(
        Uri.parse(audioUrl.startsWith('http') ? audioUrl : 'https://$audioUrl'),
        tag: MediaItem(
          id: song['id']?.toString() ?? '',
          title: song['title']?.toString() ?? 'Unknown',
          artist: song['artist']?.toString() ?? 'Unknown Artist',
          artUri: song['image_url'] != null ? Uri.parse(song['image_url']) : null,
        ),
      );

      print('Setting audio source...');
      await player.setAudioSource(audioSource);
      
      print('Starting playback...');
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);
      
      print('Playback started successfully');
      await _saveLastPlayedSong();
      
    } catch (e) {
      print('Error in playSong: $e');
      print(StackTrace.current);
      // Reset state on error
      _isPlaying = false;
      _isPlayingController.add(false);
      rethrow;
    }
    print('=== PlaySong Completed ===\n');
  }

  Future<void> togglePlayPause() async {
    try {
      if (_isPlaying) {
        await player.pause();
      } else {
        // If the song was completed, seek to start before playing
        if (player.processingState == ProcessingState.completed) {
          await player.seek(Duration.zero);
        }
        await player.play();
      }
      _isPlaying = !_isPlaying;
      _isPlayingController.add(_isPlaying);
      await _saveLastPlayedSong();
    } catch (e) {
      print('Error toggling play/pause: $e');
    }
  }

  Future<void> playNext() async {
    print('\n=== PlayNext Called ===');
    try {
      if (_queue.isEmpty) {
        print('Queue is empty, cannot play next');
        return;
      }
      
      print('Current index: $_currentIndex');
      print('Queue length: ${_queue.length}');
      
      if (_currentIndex >= _queue.length - 1) {
        print('At end of queue, no next song available');
        return;
      }
      
      _currentIndex++;
      final nextSong = _queue[_currentIndex];
      print('Playing next song: ${nextSong['title']}');
      
      // Ensure we're not in a completion state before playing
      await player.stop();
      await playSong(nextSong);
      
    } catch (e) {
      print('Error in playNext: $e');
      print(StackTrace.current);
    }
    print('=== PlayNext Completed ===\n');
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty || _currentIndex <= 0) return;
    await playSong(_queue[_currentIndex - 1]);
  }

  Future<void> dispose() async {
    await _saveLastPlayedSong();
    await player.dispose();
    await _currentSongController.close();
    await _isPlayingController.close();
  }
}