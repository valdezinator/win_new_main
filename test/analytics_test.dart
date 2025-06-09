import 'package:flutter_test/flutter_test.dart';
import 'package:your_app_name/services/analytics_service.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

@GenerateMocks([AnalyticsService])
void main() {
  group('AnalyticsService Tests', () {
    late AnalyticsService analyticsService;

    setUp(() {
      analyticsService = AnalyticsService();
    });

    test('Track event should not throw', () {
      expect(
        () => analyticsService.trackEvent('test_event', {'key': 'value'}),
        returnsNormally,
      );
    });

    test('Track error should not throw', () {
      expect(
        () => analyticsService.trackError(
          'test_error',
          'Test error message',
          {'key': 'value'},
        ),
        returnsNormally,
      );
    });

    test('Track user property should not throw', () {
      expect(
        () => analyticsService.setUserProperty('test_property', 'value'),
        returnsNormally,
      );
    });

    test('Track screen view should not throw', () {
      expect(
        () => analyticsService.trackScreenView('test_screen'),
        returnsNormally,
      );
    });
  });
} 