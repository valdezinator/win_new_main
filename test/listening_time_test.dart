import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/services/listening_time_service.dart';

void main() {
  group('ListeningTimeService Tests', () {
    late ListeningTimeService listeningTimeService;

    setUp(() {
      listeningTimeService = ListeningTimeService();
    });

    test('should initialize with zero listening time', () {
      expect(listeningTimeService.todayListeningMinutes, 0);
      expect(listeningTimeService.hasReached10Minutes, false);
      expect(listeningTimeService.isSessionActive, false);
    });

    test('should format listening time correctly', () {
      // Test with 0 minutes
      expect(listeningTimeService.getFormattedListeningTime(), '0m');
      
      // Test with 30 minutes
      listeningTimeService = ListeningTimeService();
      // We can't directly set the time, but we can test the logic
      // This would need to be tested with actual database integration
    });

    test('should calculate progress towards ads correctly', () {
      // 0 minutes should give 0.0 progress
      expect(listeningTimeService.getProgressTowardsAds(), 0.0);
      
      // 5 minutes should give 0.5 progress
      // 10 minutes should give 1.0 progress
      // This would need to be tested with actual database integration
    });

    test('should calculate minutes until ads correctly', () {
      // 0 minutes should give 10 minutes remaining
      expect(listeningTimeService.getMinutesUntilAds(), 10);
      
      // This would need to be tested with actual database integration
    });

    test('should check ad eligibility correctly', () {
      // Initially should not be eligible
      expect(listeningTimeService.canShowAds(), false);
      
      // This would need to be tested with actual database integration
    });
  });
} 