import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowService {
  static final WindowService _instance = WindowService._internal();
  factory WindowService() => _instance;
  WindowService._internal();

  static const String _windowStateKey = 'window_state';
  static const String _windowSizeKey = 'window_size';
  static const String _windowPositionKey = 'window_position';
  static const String _windowMaximizedKey = 'window_maximized';

  Future<void> initialize() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }

    try {
      await windowManager.ensureInitialized();

      // Load saved window state
      final prefs = await SharedPreferences.getInstance();
      final savedState = prefs.getString(_windowStateKey);
      
      if (savedState != null) {
        final state = Map<String, dynamic>.from(
          Map<String, dynamic>.from(
            const JsonDecoder().convert(savedState)
          )
        );

        final size = state[_windowSizeKey] as Map<String, dynamic>?;
        final position = state[_windowPositionKey] as Map<String, dynamic>?;
        final isMaximized = state[_windowMaximizedKey] as bool? ?? false;

        // Set initial window size
        if (size != null) {
          await windowManager.setSize(Size(
            (size['width'] as num).toDouble(),
            (size['height'] as num).toDouble(),
          ));
        } else {
          await windowManager.setSize(const Size(1280, 720));
        }

        // Set initial window position
        if (position != null) {
          await windowManager.setPosition(Offset(
            (position['x'] as num).toDouble(),
            (position['y'] as num).toDouble(),
          ));
        } else {
          await windowManager.center();
        }

        // Set window options
        WindowOptions windowOptions = const WindowOptions(
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.normal,
        );

        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          if (isMaximized) {
            await windowManager.maximize();
          }
          await windowManager.focus();
        });

        // Listen for window state changes
        windowManager.addListener(_WindowListener());
      } else {
        // Default window options for first run
        WindowOptions windowOptions = const WindowOptions(
          size: Size(1280, 720),
          center: true,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.normal,
        );

        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      }
    } catch (e) {
      debugPrint('Error initializing window manager: $e');
      // Continue with default window settings
    }
  }

  Future<void> saveWindowState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      final isMaximized = await windowManager.isMaximized();

      final state = {
        _windowSizeKey: {
          'width': size.width,
          'height': size.height,
        },
        _windowPositionKey: {
          'x': position.dx,
          'y': position.dy,
        },
        _windowMaximizedKey: isMaximized,
      };

      await prefs.setString(_windowStateKey, const JsonEncoder().convert(state));
    } catch (e) {
      debugPrint('Error saving window state: $e');
    }
  }
}

class _WindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await WindowService().saveWindowState();
  }

  @override
  void onWindowResize() async {
    await WindowService().saveWindowState();
  }

  @override
  void onWindowMove() async {
    await WindowService().saveWindowState();
  }

  @override
  void onWindowMaximize() async {
    await WindowService().saveWindowState();
  }

  @override
  void onWindowUnmaximize() async {
    await WindowService().saveWindowState();
  }
} 