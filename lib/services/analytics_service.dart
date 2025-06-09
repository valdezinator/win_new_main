import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  
  AnalyticsService._internal();
  
  late FirebaseAnalytics _analytics;
  bool _isInitialized = false;
  
  // Analytics event names
  static const String _eventAppStart = 'app_start';
  static const String _eventAppCrash = 'app_crash';
  static const String _eventUserLogin = 'user_login';
  static const String _eventUserLogout = 'user_logout';
  static const String _eventSongPlay = 'song_play';
  static const String _eventSongPause = 'song_pause';
  static const String _eventSongComplete = 'song_complete';
  static const String _eventAlbumView = 'album_view';
  static const String _eventSearch = 'search';
  static const String _eventDownload = 'download';
  static const String _eventError = 'error';
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize Firebase
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      
      // Initialize Sentry
      await SentryFlutter.init(
        (options) {
          options.dsn = const String.fromEnvironment('SENTRY_DSN');
          options.tracesSampleRate = 1.0;
          options.environment = kDebugMode ? 'development' : 'production';
          options.attachStacktrace = true;
          options.enableNativeCrashHandling = true;
          options.enableAutoSessionTracking = true;
        },
      );
      
      // Set up global error handling
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        _logError(
          error: details.exception,
          stackTrace: details.stack,
          context: 'Flutter Error',
        );
      };
      
      // Set up platform error handling
      PlatformDispatcher.instance.onError = (error, stack) {
        _logError(
          error: error,
          stackTrace: stack,
          context: 'Platform Error',
        );
        return true;
      };
      
      _isInitialized = true;
      logEvent(_eventAppStart);
      
    } catch (e, stack) {
      debugPrint('Error initializing analytics: $e');
      _logError(
        error: e,
        stackTrace: stack,
        context: 'Analytics Initialization',
      );
    }
  }
  
  // Log a custom event
  Future<void> logEvent(String name, {Map<String, dynamic>? parameters}) async {
    if (!_isInitialized) return;
    
    try {
      await _analytics.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('Error logging event: $e');
    }
  }
  
  // Log an error
  Future<void> _logError({
    required dynamic error,
    StackTrace? stackTrace,
    String? context,
  }) async {
    if (!_isInitialized) return;
    
    try {
      // Log to Sentry
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        hint: Hint.withMap({'context': context ?? 'Unknown context'}),
      );
      
      // Log to Firebase Analytics
      await _analytics.logEvent(
        name: _eventError,
        parameters: {
          'error_message': error.toString(),
          'error_context': context,
          'platform': Platform.operatingSystem,
          'platform_version': Platform.operatingSystemVersion,
        },
      );
    } catch (e) {
      debugPrint('Error logging error: $e');
    }
  }
  
  // Log user session
  Future<void> logUserSession(User? user) async {
    if (!_isInitialized) return;
    
    try {
      if (user != null) {
        await Sentry.configureScope((scope) {
          scope.setUser(SentryUser(
            id: user.id,
            email: user.email,
            username: user.userMetadata?['username'] as String?,
          ));
        });
        
        await _analytics.setUserId(id: user.id);
        await logEvent(_eventUserLogin, parameters: {
          'user_id': user.id,
          'email': user.email,
        });
      } else {
        await Sentry.configureScope((scope) {
          scope.setUser(null);
        });
        
        await _analytics.setUserId(id: null);
        await logEvent(_eventUserLogout);
      }
    } catch (e) {
      debugPrint('Error logging user session: $e');
    }
  }
  
  // Log song playback events
  Future<void> logSongPlayback({
    required String songId,
    required String songTitle,
    required String artistName,
    required String albumName,
    required String eventType,
  }) async {
    if (!_isInitialized) return;
    
    try {
      await logEvent(eventType, parameters: {
        'song_id': songId,
        'song_title': songTitle,
        'artist_name': artistName,
        'album_name': albumName,
      });
    } catch (e) {
      debugPrint('Error logging song playback: $e');
    }
  }
  
  // Log search events
  Future<void> logSearch({
    required String query,
    required int resultCount,
    required String resultType,
  }) async {
    if (!_isInitialized) return;
    
    try {
      await logEvent(_eventSearch, parameters: {
        'search_query': query,
        'result_count': resultCount,
        'result_type': resultType,
      });
    } catch (e) {
      debugPrint('Error logging search: $e');
    }
  }
  
  // Log download events
  Future<void> logDownload({
    required String contentId,
    required String contentType,
    required int sizeBytes,
    required bool success,
    String? errorMessage,
  }) async {
    if (!_isInitialized) return;
    
    try {
      await logEvent(_eventDownload, parameters: {
        'content_id': contentId,
        'content_type': contentType,
        'size_bytes': sizeBytes,
        'success': success,
        if (errorMessage != null) 'error_message': errorMessage,
      });
    } catch (e) {
      debugPrint('Error logging download: $e');
    }
  }
  
  // Log window state changes
  Future<void> logWindowState({
    required String state,
    required Size size,
    required Offset position,
  }) async {
    if (!_isInitialized) return;
    
    try {
      await logEvent('window_state_change', parameters: {
        'state': state,
        'width': size.width,
        'height': size.height,
        'x_position': position.dx,
        'y_position': position.dy,
      });
    } catch (e) {
      debugPrint('Error logging window state: $e');
    }
  }
  
  // Dispose analytics service
  Future<void> dispose() async {
    if (!_isInitialized) return;
    
    try {
      await Sentry.close();
    } catch (e) {
      debugPrint('Error disposing analytics: $e');
    }
  }
} 