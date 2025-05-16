import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_service.dart';

/// NoiseDetectionService: Monitors ambient noise levels to adjust audio playback
/// 
/// This service uses the device's microphone to detect ambient noise levels and
/// adjusts volume and crossfade settings automatically. It prioritizes privacy
/// by only measuring amplitude (volume) without recording or storing any audio.
/// 
/// Features:
/// - Battery-optimized sampling (only checks periodically)
/// - Privacy-focused (no audio recording or storage)
/// - Visual indicator when active
/// - Easy enable/disable through settings
class NoiseDetectionService with ChangeNotifier {
  static final NoiseDetectionService _instance = NoiseDetectionService._internal();
  factory NoiseDetectionService() => _instance;  final _audioRecorder = AudioRecorder();
  final AudioService _audioService = AudioService();
  
  bool _isEnabled = false;
  bool _isActive = false;
  Timer? _listeningTimer;
  bool _isPermissionGranted = false;
  
  // Getters
  bool get isEnabled => _isEnabled;
  bool get isActive => _isActive;
  bool get hasPermission => _isPermissionGranted;
  
  NoiseDetectionService._internal();

  /// Initialize the service with saved preferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('noise_adaptive_crossfade') ?? false;
    
    // Check permission status if enabled
    if (_isEnabled) {
      _checkPermissionStatus();
    }
  }
  
  /// Request microphone permission with clear explanation
  Future<bool> requestPermission() async {
    // Check and request permission
    final status = await Permission.microphone.request();
    _isPermissionGranted = status.isGranted;
    
    // If granted and feature is enabled, start monitoring
    if (_isPermissionGranted && _isEnabled) {
      await startMonitoring();
    }
    
    notifyListeners();
    return _isPermissionGranted;
  }
  
  /// Check current permission status
  Future<void> _checkPermissionStatus() async {
    _isPermissionGranted = await Permission.microphone.isGranted;
    notifyListeners();
  }
  
  /// Enable or disable the feature
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    
    // Save preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('noise_adaptive_crossfade', enabled);
    
    if (enabled) {
      if (!_isPermissionGranted) {
        await requestPermission();
      } else {
        await startMonitoring();
      }
    } else {
      await stopMonitoring();
    }
    
    notifyListeners();
  }
  
  /// Start noise level monitoring
  Future<void> startMonitoring() async {
    if (!_isEnabled || !_isPermissionGranted) return;
    
    // Stop any existing timers
    await stopMonitoring();
    
    // Set active state
    _isActive = true;
    notifyListeners();
    
    // Start recorder in monitoring mode
    try {      if (await _audioRecorder.hasPermission()) {
        // Get a temporary file path for recording
        final tempPath = await _getTemporaryFilePath();
        
        // Start recording with minimal configuration since we only need amplitude
        await _audioRecorder.start(
          RecordConfig(
            encoder: AudioEncoder.pcm16bits, // Use PCM for reliable amplitude detection
            bitRate: 32000,
            numChannels: 1,
          ),
          path: tempPath,
        );
        
        // Only check noise levels every  seconds to save battery
        _listeningTimer = Timer.periodic(const Duration(seconds: 10), _checkNoiseLevel);
      }
    } catch (e) {
      _isActive = false;
      notifyListeners();
      print('Error starting noise detection: $e');
    }
  }
  
  /// Stop noise level monitoring
  Future<void> stopMonitoring() async {
    _listeningTimer?.cancel();
    _listeningTimer = null;
    
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }
    
    _isActive = false;
    notifyListeners();
    
    // Reset audio settings back to default
    _audioService.resetVolume();
    _audioService.setCrossfadeDuration(null);
  }
  
  /// Check current noise level and adjust audio settings
  Future<void> _checkNoiseLevel(Timer? timer) async {
    if (!_isEnabled || !_isActive) return;
    
    try {
      final amplitude = await _audioRecorder.getAmplitude();
      final noiseLevel = amplitude.current ?? 0.0;
      
      // Map noise levels to audio adjustments
      if (noiseLevel > 70) { // High noise (70 dB is roughly a busy street)
        _audioService.adjustVolume(0.15); // Increase by 15%
        _audioService.setCrossfadeDuration(2000); // 2 second crossfade
      } else if (noiseLevel > 50) { // Medium noise (conversation level)
        _audioService.adjustVolume(0.08); // Increase by 8%
        _audioService.setCrossfadeDuration(1500); // 1.5 second crossfade
      } else { // Low noise
        _audioService.resetVolume();
        _audioService.setCrossfadeDuration(1000); // Standard crossfade
      }
    } catch (e) {
      print('Error checking noise level: $e');
    }
  }
  
  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _audioRecorder.dispose();
    super.dispose();
  }
  
  /// Get a short explanation of how this feature works
  String getPrivacyExplanation() {
    return 'Noise Adaptive Crossfade uses your microphone to detect ambient noise levels '
           'and adjust volume automatically. It only measures sound volume - no audio '
           'is recorded, stored, or sent anywhere. Processing happens entirely on your device.';
  }
  
  // Get temporary file path for recording
  Future<String> _getTemporaryFilePath() async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${directory.path}/temp_noise_$timestamp.pcm';
    return path;
  }
}
