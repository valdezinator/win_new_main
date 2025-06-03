import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class MonitoringService {
  static final MonitoringService _instance = MonitoringService._internal();
  factory MonitoringService() => _instance;
  MonitoringService._internal();

  late final FirebaseAnalytics _analytics;
  late final FirebaseCrashlytics _crashlytics;
  late final FirebasePerformance _performance;
  late final FirebaseRemoteConfig _remoteConfig;
  late final DeviceInfoPlugin _deviceInfo;
  late final PackageInfo _packageInfo;

  Future<void> initialize() async {
    try {
      // Initialize Firebase Analytics
      _analytics = FirebaseAnalytics.instance;
      await _analytics.setAnalyticsCollectionEnabled(true);
    } catch (e) {
      debugPrint('Firebase Analytics initialization failed: $e');
      // Continue without analytics
    }

    try {
      // Initialize Crashlytics
      _crashlytics = FirebaseCrashlytics.instance;
      await _crashlytics.setCrashlyticsCollectionEnabled(true);
      FlutterError.onError = _crashlytics.recordFlutterError;
    } catch (e) {
      debugPrint('Firebase Crashlytics initialization failed: $e');
      // Continue without crashlytics
    }

    try {
      // Initialize Performance Monitoring
      _performance = FirebasePerformance.instance;
      await _performance.setPerformanceCollectionEnabled(true);
    } catch (e) {
      debugPrint('Firebase Performance initialization failed: $e');
      // Continue without performance monitoring
    }

    try {
      // Initialize Remote Config
      _remoteConfig = FirebaseRemoteConfig.instance;
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      debugPrint('Firebase Remote Config initialization failed: $e');
      // Continue without remote config
    }

    // Initialize device info
    _deviceInfo = DeviceInfoPlugin();
    _packageInfo = await PackageInfo.fromPlatform();

    try {
      // Initialize Sentry
      await SentryFlutter.init(
        (options) {
          options.dsn = 'https://06217348e07f878ffd9380299c4c0d73@o4509384326774784.ingest.us.sentry.io/4509384327757824';
          options.tracesSampleRate = 1.0;
          options.environment = 'production';
        },
      );
    } catch (e) {
      debugPrint('Sentry initialization failed: $e');
      // Continue without Sentry
    }

    // Set user context
    await _setUserContext();
  }

  Future<void> _setUserContext() async {
    final deviceInfo = await _getDeviceInfo();
    await Sentry.configureScope((scope) {
      scope.setTag('app_version', _packageInfo.version);
      scope.setTag('platform', deviceInfo['platform'] ?? 'Unknown');
      scope.setTag('device_model', deviceInfo['model'] ?? 'Unknown');
    });
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    if (Platform.isWindows) {
      final windowsInfo = await _deviceInfo.windowsInfo;
      return {
        'platform': 'Windows',
        'model': windowsInfo.computerName ?? 'Unknown',
        'version': windowsInfo.displayVersion ?? 'Unknown',
      };
    } else if (Platform.isMacOS) {
      final macInfo = await _deviceInfo.macOsInfo;
      return {
        'platform': 'macOS',
        'model': macInfo.model ?? 'Unknown',
        'version': macInfo.osRelease ?? 'Unknown',
      };
    } else if (Platform.isLinux) {
      final linuxInfo = await _deviceInfo.linuxInfo;
      return {
        'platform': 'Linux',
        'model': linuxInfo.name ?? 'Unknown',
        'version': linuxInfo.version ?? 'Unknown',
      };
    }
    return {
      'platform': 'Unknown',
      'model': 'Unknown',
      'version': 'Unknown',
    };
  }

  // Analytics Methods
  Future<void> logEvent({
    required String name,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      await _analytics.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('Failed to log analytics event: $e');
    }
  }

  Future<void> setUserProperty({
    required String name,
    required String value,
  }) async {
    try {
      await _analytics.setUserProperty(
        name: name,
        value: value,
      );
    } catch (e) {
      debugPrint('Failed to set user property: $e');
    }
  }

  // Performance Monitoring
  Trace? startTrace(String name) {
    try {
      return _performance.newTrace(name);
    } catch (e) {
      debugPrint('Failed to start performance trace: $e');
      return null;
    }
  }

  // Crash Reporting
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object>? information,
    bool fatal = false,
  }) async {
    try {
      await _crashlytics.recordError(
        exception,
        stack,
        reason: reason,
        information: information ?? const [],
        fatal: fatal,
      );
    } catch (e) {
      debugPrint('Failed to record error: $e');
    }
  }

  // Remote Config
  String getString(String key) {
    try {
      return _remoteConfig.getString(key);
    } catch (e) {
      debugPrint('Failed to get remote config string: $e');
      return '';
    }
  }

  bool getBool(String key) {
    try {
      return _remoteConfig.getBool(key);
    } catch (e) {
      debugPrint('Failed to get remote config bool: $e');
      return false;
    }
  }

  int getInt(String key) {
    try {
      return _remoteConfig.getInt(key);
    } catch (e) {
      debugPrint('Failed to get remote config int: $e');
      return 0;
    }
  }

  double getDouble(String key) {
    try {
      return _remoteConfig.getDouble(key);
    } catch (e) {
      debugPrint('Failed to get remote config double: $e');
      return 0.0;
    }
  }

  // User Feedback
  void showFeedback(BuildContext context) {
    BetterFeedback.of(context).show((UserFeedback feedback) {
      // Add device info to feedback
      _getDeviceInfo().then((deviceInfo) {
        final feedbackData = {
          ...deviceInfo,
          'app_version': _packageInfo.version,
          'build_number': _packageInfo.buildNumber,
        };
        // Send feedback to your backend
        // TODO: Implement feedback submission
        debugPrint('Feedback received: ${feedback.text}');
        debugPrint('Device info: $feedbackData');
      });
    });
  }

  // Custom Performance Metrics
  Future<void> trackOperation(
    String name,
    Future<void> Function() operation,
  ) async {
    final trace = startTrace(name);
    try {
      await operation();
    } finally {
      await trace?.stop();
    }
  }

  // Cleanup
  Future<void> dispose() async {
    // Add any cleanup logic here
  }
} 