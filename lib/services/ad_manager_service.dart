import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_service.dart'; // Import AudioService
import 'listening_time_service.dart'; // Import ListeningTimeService

class AdManagerService {
  static final AdManagerService _instance = AdManagerService._internal();
  factory AdManagerService() => _instance;
  AdManagerService._internal();

  static const int AD_INTERVAL_MINUTES = 10; // Spotify-like interval
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

  // Listening time service
  final ListeningTimeService _listeningTimeService = ListeningTimeService();
  StreamSubscription? _adEligibilitySubscription;
  bool _isAdEligible = false;

  // Spotify-like ad logic fields
  Duration _activeListeningTime = Duration.zero;
  DateTime? _lastPlaybackStart;
  bool _adDue = false;

  // Ad state
  bool get isAdPlaying => _isAdPlaying;
  bool get canSkip => _canSkip;
  bool get isAdEligible => _isAdEligible;
  
  bool _wasPlayingBeforeAd = false; // Track if song was playing before ad

  // Initialize the service with the main audio player
  Future<void> initialize(AudioPlayer mainPlayer) async {
    _mainAudioPlayer = mainPlayer;
    
    // Initialize listening time service
    await _listeningTimeService.initialize();
    
    // Listen for ad eligibility changes
    _adEligibilitySubscription = _listeningTimeService.adEligibilityStream.listen((eligible) {
      _isAdEligible = eligible;
      if (eligible) {
        // User has reached 10 minutes - start ad timer
        startAdTimer();
      } else {
        // User hasn't reached 10 minutes - stop ad timer
        stopAdTimer();
      }
    });
    
    // Check initial eligibility
    _isAdEligible = _listeningTimeService.canShowAds();
    if (_isAdEligible) {
      startAdTimer();
    }
  }

  // Start the ad timer (only if user is eligible)
  void startAdTimer() {
    if (!_isAdEligible) {
      debugPrint('Ad timer not started - user has not reached 10 minutes of listening time');
      return;
    }
    
    _adTimer?.cancel();
    _adTimer = Timer(Duration(minutes: AD_INTERVAL_MINUTES), () {
      if (!_isAdPlaying && _isAdEligible) {
        playAd();
      }
    });
    debugPrint('Ad timer started - ads will play every $AD_INTERVAL_MINUTES minutes');
  }

  // Stop the ad timer
  void stopAdTimer() {
    _adTimer?.cancel();
    _adTimer = null;
    debugPrint('Ad timer stopped');
  }

  // Play an ad (only if user is eligible)
  Future<void> playAd() async {
    if (_isAdPlaying || _mainAudioPlayer == null || !_isAdEligible) {
      if (!_isAdEligible) {
        debugPrint('Ad not played - user has not reached 10 minutes of listening time');
      }
      return;
    }

    _isAdPlaying = true;
    _canSkip = false;

    // Store current song info and pause main player
    _playbackPositionBeforeAd = _mainAudioPlayer!.position;
    // Track if the song was playing before the ad
    _wasPlayingBeforeAd = _mainAudioPlayer!.playing;
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
      // Use a reliable .mp3 ad audio URL
      await _mainAudioPlayer!.setAudioSource(
        AudioSource.uri(
          Uri.parse('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'),
          tag: MediaItem(
            id: 'ad_${DateTime.now().millisecondsSinceEpoch}',
            title: 'Advertisement',
            artist: 'Sponsored Content',
          ),
        ),
      );
      await _mainAudioPlayer!.play();
      // Track ad impression
      _trackAdImpression();
    } catch (e) {
      print('Error playing ad on main player (ad may be unsupported or unreachable): $e');
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
            if (_wasPlayingBeforeAd) {
              _mainAudioPlayer!.play();
            }
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
       _wasPlayingBeforeAd = false; // Reset
    }
    
    // Restart the ad timer for the next interval (only if still eligible)
    if (_isAdEligible) {
      startAdTimer();
    }
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

  // Get listening time information
  int getTodayListeningMinutes() {
    return _listeningTimeService.todayListeningMinutes;
  }

  String getFormattedListeningTime() {
    return _listeningTimeService.getFormattedListeningTime();
  }

  double getProgressTowardsAds() {
    return _listeningTimeService.getProgressTowardsAds();
  }

  int getMinutesUntilAds() {
    return _listeningTimeService.getMinutesUntilAds();
  }

  // Refresh listening time (useful when app resumes)
  Future<void> refreshListeningTime() async {
    await _listeningTimeService.refreshListeningTime();
  }

  // Dispose resources
  void dispose() {
    _adTimer?.cancel();
    _skipTimer?.cancel();
    _adEligibilitySubscription?.cancel();
    // No _adPlayer to dispose
    // Do NOT dispose _mainAudioPlayer here as it's managed by AudioService
  }

  // Stop the current ad if playing
  void stopAd() {
    if (_isAdPlaying && _mainAudioPlayer != null) {
      _mainAudioPlayer!.stop();
      _onAdComplete();
    }
  }

  // Call this from AudioService when playback starts
  void onPlaybackStarted() {
    _lastPlaybackStart = DateTime.now();
  }

  // Call this from AudioService when playback pauses/stops
  void onPlaybackPaused() {
    if (_lastPlaybackStart != null) {
      final now = DateTime.now();
      _activeListeningTime += now.difference(_lastPlaybackStart!);
      _lastPlaybackStart = null;
      if (_activeListeningTime.inMinutes >= AD_INTERVAL_MINUTES) {
        _adDue = true;
      }
    }
  }

  // Call this from AudioService when a song finishes
  void onSongFinished() {
    onPlaybackPaused(); // Add any remaining time
  }

  // Should be called before playing a new song
  bool shouldPlayAdBeforeNextSong() {
    if (_adDue && !_isAdPlaying) {
      return true;
    }
    return false;
  }

  // Call this after ad is played
  void resetAdDue() {
    _adDue = false;
    _activeListeningTime = Duration.zero;
  }
} 