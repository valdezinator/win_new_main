import 'dart:io';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class MediaControlService {
  static final MediaControlService _instance = MediaControlService._internal();
  factory MediaControlService() => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;

  MediaControlService._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize MediaKit
    MediaKit.ensureInitialized();

    if (Platform.isWindows) {
      _initializeWindowsMediaControls();
    } else if (Platform.isMacOS) {
      _initializeMacOSMediaControls();
    } else if (Platform.isLinux) {
      _initializeLinuxMediaControls();
    }

    _isInitialized = true;
  }

  void _initializeWindowsMediaControls() {
    // Windows Media Controls
    const platform = MethodChannel('com.cresca.media_controls');
    
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playPause':
          if (_audioPlayer.playing) {
            await _audioPlayer.pause();
          } else {
            await _audioPlayer.play();
          }
          break;
        case 'next':
          // Handle next track
          break;
        case 'previous':
          // Handle previous track
          break;
        case 'stop':
          await _audioPlayer.stop();
          break;
      }
    });
  }

  void _initializeMacOSMediaControls() {
    // macOS Media Controls
    const platform = MethodChannel('com.cresca.media_controls');
    
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playPause':
          if (_audioPlayer.playing) {
            await _audioPlayer.pause();
          } else {
            await _audioPlayer.play();
          }
          break;
        case 'next':
          // Handle next track
          break;
        case 'previous':
          // Handle previous track
          break;
        case 'stop':
          await _audioPlayer.stop();
          break;
      }
    });
  }

  void _initializeLinuxMediaControls() {
    // Linux Media Controls
    const platform = MethodChannel('com.cresca.media_controls');
    
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playPause':
          if (_audioPlayer.playing) {
            await _audioPlayer.pause();
          } else {
            await _audioPlayer.play();
          }
          break;
        case 'next':
          // Handle next track
          break;
        case 'previous':
          // Handle previous track
          break;
        case 'stop':
          await _audioPlayer.stop();
          break;
      }
    });
  }

  Future<void> updateMediaControls({
    required String title,
    required String artist,
    required String album,
    String? artworkUrl,
    required Duration duration,
    required Duration position,
    required bool isPlaying,
  }) async {
    if (!_isInitialized) return;

    if (Platform.isWindows) {
      await _updateWindowsMediaControls(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        duration: duration,
        position: position,
        isPlaying: isPlaying,
      );
    } else if (Platform.isMacOS) {
      await _updateMacOSMediaControls(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        duration: duration,
        position: position,
        isPlaying: isPlaying,
      );
    } else if (Platform.isLinux) {
      await _updateLinuxMediaControls(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        duration: duration,
        position: position,
        isPlaying: isPlaying,
      );
    }
  }

  Future<void> _updateWindowsMediaControls({
    required String title,
    required String artist,
    required String album,
    String? artworkUrl,
    required Duration duration,
    required Duration position,
    required bool isPlaying,
  }) async {
    const platform = MethodChannel('com.cresca.media_controls');
    
    try {
      await platform.invokeMethod('updateMediaControls', {
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'duration': duration.inMilliseconds,
        'position': position.inMilliseconds,
        'isPlaying': isPlaying,
      });
    } catch (e) {
      print('Error updating Windows media controls: $e');
    }
  }

  Future<void> _updateMacOSMediaControls({
    required String title,
    required String artist,
    required String album,
    String? artworkUrl,
    required Duration duration,
    required Duration position,
    required bool isPlaying,
  }) async {
    const platform = MethodChannel('com.cresca.media_controls');
    
    try {
      await platform.invokeMethod('updateMediaControls', {
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'duration': duration.inMilliseconds,
        'position': position.inMilliseconds,
        'isPlaying': isPlaying,
      });
    } catch (e) {
      print('Error updating macOS media controls: $e');
    }
  }

  Future<void> _updateLinuxMediaControls({
    required String title,
    required String artist,
    required String album,
    String? artworkUrl,
    required Duration duration,
    required Duration position,
    required bool isPlaying,
  }) async {
    const platform = MethodChannel('com.cresca.media_controls');
    
    try {
      await platform.invokeMethod('updateMediaControls', {
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'duration': duration.inMilliseconds,
        'position': position.inMilliseconds,
        'isPlaying': isPlaying,
      });
    } catch (e) {
      print('Error updating Linux media controls: $e');
    }
  }

  Future<void> dispose() async {
    if (!_isInitialized) return;

    if (Platform.isWindows) {
      await _disposeWindowsMediaControls();
    } else if (Platform.isMacOS) {
      await _disposeMacOSMediaControls();
    } else if (Platform.isLinux) {
      await _disposeLinuxMediaControls();
    }

    await _audioPlayer.dispose();
    _isInitialized = false;
  }

  Future<void> _disposeWindowsMediaControls() async {
    const platform = MethodChannel('com.cresca.media_controls');
    try {
      await platform.invokeMethod('dispose');
    } catch (e) {
      print('Error disposing Windows media controls: $e');
    }
  }

  Future<void> _disposeMacOSMediaControls() async {
    const platform = MethodChannel('com.cresca.media_controls');
    try {
      await platform.invokeMethod('dispose');
    } catch (e) {
      print('Error disposing macOS media controls: $e');
    }
  }

  Future<void> _disposeLinuxMediaControls() async {
    const platform = MethodChannel('com.cresca.media_controls');
    try {
      await platform.invokeMethod('dispose');
    } catch (e) {
      print('Error disposing Linux media controls: $e');
    }
  }
} 