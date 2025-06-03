import 'dart:io';
import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:just_audio/just_audio.dart';

class SystemTrayService {
  static final SystemTrayService _instance = SystemTrayService._internal();
  factory SystemTrayService() => _instance;

  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();
  bool _isInitialized = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Constants for system tray events
  static const String kSystemTrayEventClick = 'click';

  SystemTrayService._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await _initializeSystemTray();
    }

    _isInitialized = true;
  }

  Future<void> _initializeSystemTray() async {
    // Initialize system tray
    await _systemTray.initSystemTray(
      title: "Cresca",
      iconPath: Platform.isWindows
          ? 'assets/icons/app_icon.ico'
          : 'assets/icons/app_icon.png',
    );

    // Create menu items
    await _menu.buildFrom([
      MenuItemLabel(
        label: 'Show/Hide',
        onClicked: (menuItem) => _toggleWindow(),
      ),
      MenuItemLabel(
        label: 'Play/Pause',
        onClicked: (menuItem) => _togglePlayback(),
      ),
      MenuItemLabel(
        label: 'Next Track',
        onClicked: (menuItem) => _nextTrack(),
      ),
      MenuItemLabel(
        label: 'Previous Track',
        onClicked: (menuItem) => _previousTrack(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Exit',
        onClicked: (menuItem) => _exitApp(),
      ),
    ]);

    // Set the menu
    await _systemTray.setContextMenu(_menu);

    // Handle system tray click
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        _toggleWindow();
      }
    });
  }

  Future<void> _toggleWindow() async {
    final window = await windowManager.isVisible();
    if (window) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  Future<void> _nextTrack() async {
    // Implement next track functionality
  }

  Future<void> _previousTrack() async {
    // Implement previous track functionality
  }

  Future<void> _exitApp() async {
    await _systemTray.destroy();
    exit(0);
  }

  Future<void> dispose() async {
    if (!_isInitialized) return;
    await _systemTray.destroy();
    _isInitialized = false;
  }
} 