import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_service.dart'; // Import AudioService

class AdManagerService {
  static final AdManagerService _instance = AdManagerService._internal();
  factory AdManagerService() => _instance;
  AdManagerService._internal();

  static const int AD_INTERVAL_MINUTES = 1;
  static const int SKIP_DELAY_SECONDS = 5;
  
  Timer? _adTimer;
  Timer? _skipTimer;
  bool _isAdPlaying = false;
  bool _canSkip = false;
  
  // Reference to the main audio player
  AudioPlayer? _mainAudioPlayer;
  Duration? _playbackPositionBeforeAd;
  Uri? _currentSongUri;
  Object? _currentSongTag;

  // Ad state
  bool get isAdPlaying => _isAdPlaying;
  bool get canSkip => _canSkip;
  
  // Initialize the service with the main audio player
  Future<void> initialize(AudioPlayer mainPlayer) async {
    _mainAudioPlayer = mainPlayer;
    // The ad playback will use the main player, no need to set loop mode here.
    // We will add listeners to the main player's state in playAd.
  }

  // Start the ad timer
  void startAdTimer() {
    _adTimer?.cancel();
    _adTimer = Timer(Duration(minutes: AD_INTERVAL_MINUTES), () {
      if (!_isAdPlaying) {
        playAd();
      }
    });
  }

  // Play an ad
  Future<void> playAd() async {
    if (_isAdPlaying || _mainAudioPlayer == null) return;

    _isAdPlaying = true;
    _canSkip = false;

    // Store current song info and pause main player
    _playbackPositionBeforeAd = _mainAudioPlayer!.position;
    // Store the current audio source to resume the original song after the ad.
    // We need a way to get the original AudioSource back. Storing the URI and tag might work.
    // Note: This assumes the original song was loaded via setUrl or setAudioSource with a tag.
    try {
       _currentSongUri = (_mainAudioPlayer!.sequenceState?.currentSource as UriAudioSource?)?.uri;
       _currentSongTag = _mainAudioPlayer!.sequenceState?.currentSource?.tag;
    } catch (e) {
      print('Could not get current song info: $e');
      _currentSongUri = null;
      _currentSongTag = null;
    }
    
    await _mainAudioPlayer!.pause();
    
    // Start skip timer
    _skipTimer?.cancel();
    _skipTimer = Timer(Duration(seconds: SKIP_DELAY_SECONDS), () {
      _canSkip = true;
    });

    // Listen for the ad to complete using the main player
    StreamSubscription? adCompletionSubscription;
    adCompletionSubscription = _mainAudioPlayer!.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        adCompletionSubscription?.cancel(); // Only listen for one completion
        _onAdComplete();
      }
    });

    try {
      // TODO: Replace with actual ad audio URL
      // Play the ad using the main player
      await _mainAudioPlayer!.setUrl('https://file-examples.com/storage/v1/2017/11/file_example_WAV_1MG.wav'); // Using a sample URL
      await _mainAudioPlayer!.play();
      
      // Track ad impression
      _trackAdImpression();
    } catch (e) {
      print('Error playing ad on main player: $e');
      // If ad fails to load/play, just complete the ad process
      _onAdComplete();
      adCompletionSubscription?.cancel(); // Ensure listener is cancelled on error
    }
  }

  // Skip the current ad
  Future<void> skipAd() async {
    if (!_canSkip || _mainAudioPlayer == null) return;
    
    await _mainAudioPlayer!.stop(); // Stop the ad playback
    _onAdComplete(); // Trigger completion logic
  }

  // Handle ad completion
  void _onAdComplete() {
    _isAdPlaying = false;
    _canSkip = false;
    _skipTimer?.cancel();
    
    // Resume main player with the original song
    if (_mainAudioPlayer != null) {
       // Try to load the original song back
       if (_currentSongUri != null) {
          try {
            _mainAudioPlayer!.setUrl(_currentSongUri.toString(), initialPosition: _playbackPositionBeforeAd, tag: _currentSongTag); // Reload with original position and tag
            _mainAudioPlayer!.play();
          } catch (e) {
             print('Error resuming original song: $e');
             // Handle error resuming - maybe just start the timer and leave player stopped
          }
       } else {
          // If original song info wasn't available, just start the timer
          print('Original song info not available to resume.');
       }
       _playbackPositionBeforeAd = null; // Clear stored position
       _currentSongUri = null; // Clear stored URI
       _currentSongTag = null; // Clear stored tag
    }
    
    startAdTimer(); // Restart the ad timer for the next interval
  }

  // Track ad impression
  Future<void> _trackAdImpression() async {
    // TODO: Implement analytics tracking
  }

  // Save user preferences
  Future<void> saveAdPreferences({
    required int adFrequency,
    required DateTime doNotDisturbStart,
    required DateTime doNotDisturbEnd,
    required List<String> categories,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ad_frequency', adFrequency);
    await prefs.setString('dnd_start', doNotDisturbStart.toIso8601String());
    await prefs.setString('dnd_end', doNotDisturbEnd.toIso8601String());
    await prefs.setStringList('ad_categories', categories);
  }

  // Load user preferences
  Future<Map<String, dynamic>> loadAdPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'ad_frequency': prefs.getInt('ad_frequency') ?? AD_INTERVAL_MINUTES,
      'dnd_start': prefs.getString('dnd_start'),
      'dnd_end': prefs.getString('dnd_end'),
      'categories': prefs.getStringList('ad_categories') ?? [],
    };
  }

  // Dispose resources
  void dispose() {
    _adTimer?.cancel();
    _skipTimer?.cancel();
    // No _adPlayer to dispose
    // Do NOT dispose _mainAudioPlayer here as it's managed by AudioService
  }
} 