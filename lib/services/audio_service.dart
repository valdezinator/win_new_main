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
      // Setup state change handler with auto-play functionality
    player.playerStateStream.listen((state) async {
      print('\n=== Player State Changed ===');
      print('Processing State: ${state.processingState}');
      print('Playing: ${state.playing}');
      
      if (state.processingState == ProcessingState.completed) {
        print('Song completed naturally, preparing to play next...');
        
        if (_currentIndex < _queue.length - 1) {
          // Don't stop or reset - just move to next song
          print('Playing next song in queue (${_currentIndex + 1}/${_queue.length})');
          await playNext();
        } else {
          print('Reached end of queue');
          _isPlaying = false;
          _isPlayingController.add(false);
          await player.stop();
          await player.seek(Duration.zero);
        }
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
    try {
      print('=== Starting PlaySong for ${song['title']} ===');
      print('Audio URL: ${song['audio_url']}');
      
      if (song['audio_url'] == null) {
        print('Error: No audio URL provided');
        return;
      }

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
        'queue': song['queue'], // Keep the queue from the original song object
      };

      // Stop current playback first
      print('Stopping current playback...');
      await player.stop();

      // Update the current song and queue state
      _currentSong = song;
      _currentSongController.add(song);
      
      if (song['queue'] != null) {
        _queue = List<Map<String, dynamic>>.from(song['queue']);
        _currentIndex = _queue.indexWhere((s) => s['id'] == song['id']);
      }      // Create the audio source with proper media item
      final audioSource = AudioSource.uri(
        Uri.parse(processedSong['audio_url']),
        tag: MediaItem(
          id: processedSong['id']?.toString() ?? '',
          title: processedSong['title']?.toString() ?? 'Unknown',
          artist: processedSong['artist']?.toString() ?? 'Unknown Artist',
          duration: processedSong['duration'] != null 
              ? Duration(seconds: processedSong['duration'] is int 
                  ? processedSong['duration'] 
                  : int.tryParse(processedSong['duration'].toString()) ?? 0)
              : null,
          artUri: processedSong['image_url'] != null ? Uri.parse(processedSong['image_url']) : null,
        ),
      );      try {
        // Set the audio source and start playing
        await player.setAudioSource(audioSource, initialPosition: Duration.zero);
        
        // Update state before starting playback
        _currentSong = processedSong;
        if (processedSong['queue'] != null) {
          _queue = List<Map<String, dynamic>>.from(processedSong['queue']);
          _currentIndex = _queue.indexWhere((s) => s['id'] == processedSong['id']);
        }
        _currentSongController.add(processedSong);
        
        // Start playback
        await player.play();
        _isPlaying = true;
        _isPlayingController.add(true);
        
        // Save state after successful playback start
        await _saveLastPlayedSong();
        
        print('=== PlaySong Completed Successfully for ${processedSong['title']} ===\\n');
      } catch (e) {
        print('Error during audio source setup or playback: $e');
        throw e; // Re-throw to be caught by outer try-catch
      }
    } catch (e, stackTrace) {
      print('Error in playSong for ${song['title']}: $e');
      print('Stack trace: $stackTrace');
      _isPlaying = false;
      _isPlayingController.add(false);
      rethrow;
    }
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
        
        // Ensure we preserve all required metadata when constructing the next song
        Map<String, dynamic> songToPlay = {
          ...Map<String, dynamic>.from(nextSongMap),
          'queue': _queue,
          'album': nextSongMap['album'] ?? _currentSong?['album'],
          'album_id': nextSongMap['album_id'] ?? _currentSong?['album_id'],
          'album_art': nextSongMap['album_art'] ?? nextSongMap['image_url'] ?? _currentSong?['album_art'],
          'artist': nextSongMap['artist'] ?? _currentSong?['artist'] ?? 'Unknown Artist',
          'duration': nextSongMap['duration'],
        };

        // Play the song without stopping the current one first
        final audioSource = AudioSource.uri(
          Uri.parse(songToPlay['audio_url']),
          tag: MediaItem(
            id: songToPlay['id']?.toString() ?? '',
            title: songToPlay['title']?.toString() ?? 'Unknown',
            artist: songToPlay['artist']?.toString() ?? 'Unknown Artist',
            duration: songToPlay['duration'] != null 
                ? Duration(seconds: songToPlay['duration'] is int 
                    ? songToPlay['duration'] 
                    : int.tryParse(songToPlay['duration'].toString()) ?? 0)
                : null,
            artUri: songToPlay['image_url'] != null ? Uri.parse(songToPlay['image_url']) : null,
          ),
        );

        // Set the audio source and start playing immediately
        await player.setAudioSource(audioSource);
        await player.play();
        
        // Update state
        _currentSong = songToPlay;
        _currentSongController.add(songToPlay);
        _isPlaying = true;
        _isPlayingController.add(true);
        
        // Save state
        await _saveLastPlayedSong();

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