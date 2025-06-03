import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:feedback/feedback.dart';
import '../lib/services/monitoring_service.dart';

@GenerateMocks([
  FirebaseAnalytics,
  FirebaseCrashlytics,
  FirebasePerformance,
  FirebaseRemoteConfig,
  DeviceInfoPlugin,
  PackageInfo,
  Trace,
])
void main() {
  late MonitoringService monitoringService;
  late MockFirebaseAnalytics mockAnalytics;
  late MockFirebaseCrashlytics mockCrashlytics;
  late MockFirebasePerformance mockPerformance;
  late MockFirebaseRemoteConfig mockRemoteConfig;
  late MockDeviceInfoPlugin mockDeviceInfo;
  late MockPackageInfo mockPackageInfo;
  late MockTrace mockTrace;

  setUp(() {
    mockAnalytics = MockFirebaseAnalytics();
    mockCrashlytics = MockFirebaseCrashlytics();
    mockPerformance = MockFirebasePerformance();
    mockRemoteConfig = MockFirebaseRemoteConfig();
    mockDeviceInfo = MockDeviceInfoPlugin();
    mockPackageInfo = MockPackageInfo();
    mockTrace = MockTrace();

    monitoringService = MonitoringService();
  });

  group('MonitoringService', () {
    test('initialize sets up all services', () async {
      // Arrange
      when(mockAnalytics.setAnalyticsCollectionEnabled(true))
          .thenAnswer((_) async => null);
      when(mockCrashlytics.setCrashlyticsCollectionEnabled(true))
          .thenAnswer((_) async => null);
      when(mockPerformance.setPerformanceCollectionEnabled(true))
          .thenAnswer((_) async => null);
      when(mockRemoteConfig.setConfigSettings(any))
          .thenAnswer((_) async => null);
      when(mockRemoteConfig.fetchAndActivate())
          .thenAnswer((_) async => true);

      // Act
      await monitoringService.initialize();

      // Assert
      verify(mockAnalytics.setAnalyticsCollectionEnabled(true)).called(1);
      verify(mockCrashlytics.setCrashlyticsCollectionEnabled(true)).called(1);
      verify(mockPerformance.setPerformanceCollectionEnabled(true)).called(1);
      verify(mockRemoteConfig.setConfigSettings(any)).called(1);
      verify(mockRemoteConfig.fetchAndActivate()).called(1);
    });

    test('logEvent calls analytics with correct parameters', () async {
      // Arrange
      const eventName = 'test_event';
      final parameters = {'key': 'value'};

      // Act
      await monitoringService.logEvent(
        name: eventName,
        parameters: parameters,
      );

      // Assert
      verify(mockAnalytics.logEvent(
        name: eventName,
        parameters: parameters,
      )).called(1);
    });

    test('recordError calls crashlytics with correct parameters', () async {
      // Arrange
      final exception = Exception('Test error');
      final stackTrace = StackTrace.current;

      // Act
      await monitoringService.recordError(
        exception,
        stackTrace,
        reason: 'Test reason',
        fatal: true,
      );

      // Assert
      verify(mockCrashlytics.recordError(
        exception,
        stackTrace,
        reason: 'Test reason',
        fatal: true,
      )).called(1);
    });

    test('startTrace creates new trace', () {
      // Arrange
      const traceName = 'test_trace';
      when(mockPerformance.newTrace(traceName)).thenReturn(mockTrace);

      // Act
      final trace = monitoringService.startTrace(traceName);

      // Assert
      verify(mockPerformance.newTrace(traceName)).called(1);
      expect(trace, equals(mockTrace));
    });

    test('getString returns remote config value', () {
      // Arrange
      const key = 'test_key';
      const value = 'test_value';
      when(mockRemoteConfig.getString(key)).thenReturn(value);

      // Act
      final result = monitoringService.getString(key);

      // Assert
      verify(mockRemoteConfig.getString(key)).called(1);
      expect(result, equals(value));
    });

    test('trackOperation measures operation duration', () async {
      // Arrange
      const operationName = 'test_operation';
      when(mockPerformance.newTrace(operationName)).thenReturn(mockTrace);
      when(mockTrace.stop()).thenAnswer((_) async => null);

      // Act
      await monitoringService.trackOperation(
        operationName,
        () async {
          await Future.delayed(const Duration(milliseconds: 100));
        },
      );

      // Assert
      verify(mockPerformance.newTrace(operationName)).called(1);
      verify(mockTrace.stop()).called(1);
    });
  });
} 