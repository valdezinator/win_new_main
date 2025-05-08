import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

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
        // Ensure the queue in _currentSong is the most up-to-date one from the service's state
        _currentSong!['queue'] = _queue; 
        await prefs.setString('last_played_song', json.encode(_currentSong));
        await prefs.setBool('was_playing', _isPlaying);
      }
    } catch (e) {
      print('Error saving last played song: $e');
    }
  }

  Future<void> playSong(Map<String, dynamic> song) async {
    print('\\\\n=== PlaySong Called ===');
    print('Song data: ${song.toString()}');
    
    try {
      print('Stopping current playback...');
      await player.stop();
      
      // Reset player state if it was completed to allow replaying the same source if needed
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      
      String? audioUrl = song['audio_url']?.toString();
      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('Invalid audio URL: $audioUrl');
      }

      // Ensure URL is properly formatted
      if (!audioUrl.startsWith('http://') && !audioUrl.startsWith('https://')) {
        audioUrl = 'https://$audioUrl'; // Default to https if no scheme
      }
      print('Audio URL: $audioUrl');

      // Fetch duration if not available
      if (song['duration'] == null) {
        try {
          final durationPlayer = AudioPlayer();
          final duration = await durationPlayer.setUrl(audioUrl); // setUrl might throw
          song['duration'] = duration?.inSeconds;
          await durationPlayer.dispose();
        } catch (e) {
          print('Error fetching duration for ${song['title']}: $e');
          // Continue without duration, or set a default, or rethrow if critical
        }
      }

      // Set the current song internally
      _currentSong = Map<String, dynamic>.from(song); 

      // Manage the queue
      if (song['queue'] != null && (song['queue'] as List).isNotEmpty) {
        // If the incoming song map has a queue, that becomes the authoritative queue
        _queue = List<Map<String, dynamic>>.from(song['queue']);
        _currentIndex = _queue.indexWhere((s) => s['id'] == _currentSong!['id']);
        
        if (_currentIndex == -1) { 
            print('Warning: Song ID ${_currentSong!['id']} not found in its provided queue. Adding it to the start.');
            _queue.insert(0, _currentSong!); // Add to the start if not found
            _currentIndex = 0;
        }
      } else {
        // No queue provided with the song, or an empty queue.
        // Start a new queue with just this song.
        print('No valid queue in song object. Setting queue to this song only: ${_currentSong!['title']}');
        _queue = [_currentSong!];
        _currentIndex = 0;
      }
      // CRITICAL: Ensure the _currentSong map itself reflects the authoritative queue for broadcasts and saving
      _currentSong!['queue'] = _queue; 

      // Broadcast the updated song (which now includes the correct queue)
      _currentSongController.add(_currentSong!); 
      
      final audioSource = AudioSource.uri(
        Uri.parse(audioUrl),
        tag: MediaItem(
          id: _currentSong!['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(), // Ensure ID is never empty
          title: _currentSong!['title']?.toString() ?? 'Unknown Title',
          artist: _currentSong!['artist']?.toString() ?? 'Unknown Artist',
          artUri: _currentSong!['image_url'] != null ? Uri.parse(_currentSong!['image_url']) : null,
          album: _currentSong!['album_title']?.toString() ?? _currentSong!['album']?.toString(), // Prefer album_title
          duration: song['duration'] != null ? Duration(seconds: song['duration']) : null,
        ),
      );

      print('Setting audio source for: ${_currentSong!['title']}');
      await player.setAudioSource(audioSource);
      
      print('Starting playback for: ${_currentSong!['title']}');
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);
      
      print('Playback started successfully for: ${_currentSong!['title']}');
      await _saveLastPlayedSong(); // Save state including the new queue
      
    } catch (e) {
      print('Error in playSong for ${song['title']}: $e');
      _isPlaying = false;
      _isPlayingController.add(false);
      // Optionally rethrow or handle specific errors (e.g., network issues)
      // rethrow; 
    }
    print('=== PlaySong Completed for ${song['title']} ===\\\\n');
  }

  // Plays song with caching
  Future<void> playSongWithCache(Map<String, dynamic> song) async {
    final String url = song['audio_url'];
    final String localPath = await _getCachedFilePath(url);
    final File file = File(localPath);
    if (!await file.exists()) {
      // Download and cache audio if not already cached
      final response = await http.get(Uri.parse(url));
      await file.writeAsBytes(response.bodyBytes);
    }
    // Play from local file
    await player.setFilePath(localPath);
    player.play();
  }

  // Helper: get file path in cache dir for a given URL
  Future<String> _getCachedFilePath(String url) async {
    final Directory cacheDir = await getTemporaryDirectory();
    final String fileName = url.hashCode.toString(); // simple hash as filename
    return "${cacheDir.path}/$fileName.mp3";
  }

  Future<void> togglePlayPause() async {
    print('\\\\n=== TogglePlayPause Called ===');
    try {
      if (_isPlaying) {
        print('Pausing playback.');
        await player.pause();
        _isPlaying = false;
      } else {
        if (player.audioSource != null && _currentSong != null) { // Check _currentSong too
          print('Resuming playback for: ${_currentSong!['title']}');
          await player.play();
          _isPlaying = true;
        } else if (_currentSong != null) {
          // If no audio source (e.g., after app restart or error), try to play _currentSong
          print('No audio source, attempting to play current song: ${_currentSong!['title']}');
          await playSong(_currentSong!); // playSong will set up source and queue
        } else {
          print('No current song to play or resume.');
        }
      }
      _isPlayingController.add(_isPlaying);
      await _saveLastPlayedSong();
    } catch (e) {
      print('Error in togglePlayPause: $e');
      // Consider resetting state if error is critical
    }
    print('=== TogglePlayPause Completed ===\\\\n');
  }

  Future<void> playNext() async {
    print('\\\\n=== PlayNext Called ===');
    try {
      if (_queue.isEmpty) {
        print('Queue is empty. Cannot play next.');
        if (player.playing) await player.stop();
        _isPlaying = false;
        _isPlayingController.add(false);
        return;
      }

      if (_currentIndex + 1 < _queue.length) {
        _currentIndex++;
        final nextSongMap = _queue[_currentIndex];
        print('Preparing to play next song: ${nextSongMap['title']} (ID: ${nextSongMap['id']})');
        
        // Construct the song map for playSong. It's crucial that this map
        // carries the *current, authoritative queue* from the AudioService.
        Map<String, dynamic> songToPlay = Map<String, dynamic>.from(nextSongMap);
        songToPlay['queue'] = _queue; // Pass the current full queue

        await playSong(songToPlay); // playSong will handle all setup and broadcasts

      } else {
        print('End of queue reached.');
        if (player.playing) await player.stop();
        _isPlaying = false;
        _isPlayingController.add(false);
        // Keep _currentSong as the last played song, but update its controller
        // to reflect it's no longer playing and is at the end of the queue.
        if (_currentSong != null) {
           _currentSong!['queue'] = _queue; // Ensure queue is still attached
           _currentSongController.add(_currentSong!); 
        }
      }
    } catch (e) {
      print('Error in playNext: $e');
      _isPlaying = false;
      _isPlayingController.add(false);
    }
    print('=== PlayNext Completed ===\\\\n');
  }

  Future<void> playPrevious() async {
    print('\\\\n=== PlayPrevious Called ===');
    if (_queue.isEmpty) {
        print('Queue is empty. Cannot play previous.');
        return;
    }

    // If more than a few seconds (e.g., 3s) into the current song, restart it
    if (player.position > const Duration(seconds: 3) && 
        _currentIndex >= 0 && _currentIndex < _queue.length) {
        print('Restarting current song: ${_queue[_currentIndex]['title']}');
        await player.seek(Duration.zero);
        if (!_isPlaying && player.audioSource != null) { // If paused and source exists, start playing
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
      print('Preparing to play previous song: ${prevSongMap['title']} (ID: ${prevSongMap['id']})');

      Map<String, dynamic> songToPlay = Map<String, dynamic>.from(prevSongMap);
      songToPlay['queue'] = _queue; // Pass the current full queue

      await playSong(songToPlay); // playSong handles setup

    } else {
      // At the beginning of the queue (or if _currentIndex became < 0 unexpectedly)
      // Replay the first song from the beginning.
      print('Beginning of queue reached or song just started. Replaying first song.');
      if (_queue.isNotEmpty) { // Ensure queue still has items
        _currentIndex = 0; // Explicitly set to first song's index
        final firstSongMap = _queue[0];
        Map<String, dynamic> songToPlay = Map<String, dynamic>.from(firstSongMap);
        songToPlay['queue'] = _queue;
        
        await playSong(songToPlay); 
        // playSong should handle playing, but ensure seek to zero if it was already this song
        await player.seek(Duration.zero); 
        if (!_isPlaying && player.audioSource != null) { 
            await player.play();
            _isPlaying = true;
            _isPlayingController.add(true);
        }
      } else {
        print('Queue is empty, cannot replay first song.');
      }
    }
    print('=== PlayPrevious Completed ===\\\\n');
  }

  // Play the current audio
  Future<void> play() async {
    if (player.playing) return; // Already playing
    
    try {
      await player.play();
      _isPlaying = true;
      _isPlayingController.add(true);
    } catch (e) {
      print('Error playing audio: $e');
      _isPlaying = false;
      _isPlayingController.add(false);
    }
  }
  
  // Pause the current audio
  Future<void> pause() async {
    if (!player.playing) return; // Already paused
    
    try {
      await player.pause();
      _isPlaying = false;
      _isPlayingController.add(false);
    } catch (e) {
      print('Error pausing audio: $e');
    }
  }

  Future<void> dispose() async {
    await _saveLastPlayedSong();
    await player.dispose();
    await _currentSongController.close();
    await _isPlayingController.close();
  }
}