import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ListeningTimeService extends ChangeNotifier {
  static final ListeningTimeService _instance = ListeningTimeService._internal();
  factory ListeningTimeService() => _instance;
  ListeningTimeService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Session tracking
  String? _currentSessionId;
  DateTime? _sessionStartTime;
  bool _isSessionActive = false;
  Timer? _updateTimer;
  
  // Today's listening time
  int _todayListeningMinutes = 0;
  bool _hasReached10Minutes = false;
  
  // Stream controllers
  final StreamController<int> _listeningTimeController = StreamController<int>.broadcast();
  final StreamController<bool> _adEligibilityController = StreamController<bool>.broadcast();
  
  // Getters
  Stream<int> get listeningTimeStream => _listeningTimeController.stream;
  Stream<bool> get adEligibilityStream => _adEligibilityController.stream;
  int get todayListeningMinutes => _todayListeningMinutes;
  bool get hasReached10Minutes => _hasReached10Minutes;
  bool get isSessionActive => _isSessionActive;
  
  // Initialize the service
  Future<void> initialize() async {
    await _loadTodayListeningTime();
    await _checkAdEligibility();
  }
  
  // Start a new listening session
  Future<void> startSession() async {
    if (_isSessionActive) return;
    
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      
      // Call the database function to start a new session
      final response = await _supabase.rpc('start_listening_session', params: {
        'p_user_id': user.id,
      });
      
      _currentSessionId = response;
      _sessionStartTime = DateTime.now();
      _isSessionActive = true;
      
      // Start periodic updates
      _startPeriodicUpdates();
      
      notifyListeners();
      debugPrint('Listening session started: $_currentSessionId');
    } catch (e) {
      debugPrint('Error starting listening session: $e');
    }
  }
  
  // End the current listening session
  Future<void> endSession() async {
    if (!_isSessionActive) return;
    
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      
      // Calculate session duration
      final sessionDuration = _sessionStartTime != null 
          ? DateTime.now().difference(_sessionStartTime!).inMinutes 
          : 0;
      
      // Call the database function to end the session
      await _supabase.rpc('end_listening_session', params: {
        'p_user_id': user.id,
        'p_minutes_listened': sessionDuration,
      });
      
      // Update local state
      _todayListeningMinutes += sessionDuration;
      _currentSessionId = null;
      _sessionStartTime = null;
      _isSessionActive = false;
      
      // Stop periodic updates
      _stopPeriodicUpdates();
      
      // Check ad eligibility
      await _checkAdEligibility();
      
      notifyListeners();
      _listeningTimeController.add(_todayListeningMinutes);
      debugPrint('Listening session ended. Duration: $sessionDuration minutes');
    } catch (e) {
      debugPrint('Error ending listening session: $e');
    }
  }
  
  // Update listening time periodically
  void _startPeriodicUpdates() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (_isSessionActive) {
        await _updateListeningTime();
      }
    });
  }
  
  void _stopPeriodicUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }
  
  // Update listening time and check ad eligibility
  Future<void> _updateListeningTime() async {
    if (!_isSessionActive || _sessionStartTime == null) return;
    
    final sessionDuration = DateTime.now().difference(_sessionStartTime!).inMinutes;
    final previousTotal = _todayListeningMinutes;
    
    // Load fresh data from database
    await _loadTodayListeningTime();
    
    // Add current session time
    _todayListeningMinutes += sessionDuration;
    
    // Check if we've crossed the 10-minute threshold
    if (!_hasReached10Minutes && _todayListeningMinutes >= 10) {
      _hasReached10Minutes = true;
      _adEligibilityController.add(true);
      debugPrint('User has reached 10 minutes of listening time - ads are now eligible');
    }
    
    if (_todayListeningMinutes != previousTotal) {
      notifyListeners();
      _listeningTimeController.add(_todayListeningMinutes);
    }
  }
  
  // Load today's listening time from database
  Future<void> _loadTodayListeningTime() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      
      final response = await _supabase.rpc('get_user_today_listening_minutes', params: {
        'p_user_id': user.id,
      });
      
      _todayListeningMinutes = response ?? 0;
      await _checkAdEligibility();
      
      notifyListeners();
      _listeningTimeController.add(_todayListeningMinutes);
    } catch (e) {
      debugPrint('Error loading today\'s listening time: $e');
    }
  }
  
  // Check if user is eligible for ads (has listened for at least 10 minutes)
  Future<void> _checkAdEligibility() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      
      final response = await _supabase.rpc('has_user_listened_10_minutes_today', params: {
        'p_user_id': user.id,
      });
      
      _hasReached10Minutes = response ?? false;
      _adEligibilityController.add(_hasReached10Minutes);
    } catch (e) {
      debugPrint('Error checking ad eligibility: $e');
    }
  }
  
  // Get user's listening statistics
  Future<Map<String, dynamic>> getListeningStats({int days = 30}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return {};
      
      final response = await _supabase.rpc('get_user_listening_stats', params: {
        'p_user_id': user.id,
        'p_days': days,
      });
      
      if (response != null && response.isNotEmpty) {
        return {
          'total_minutes': response[0]['total_minutes'] ?? 0,
          'total_sessions': response[0]['total_sessions'] ?? 0,
          'average_minutes_per_day': response[0]['average_minutes_per_day'] ?? 0.0,
          'longest_session_minutes': response[0]['longest_session_minutes'] ?? 0,
        };
      }
      
      return {};
    } catch (e) {
      debugPrint('Error getting listening stats: $e');
      return {};
    }
  }
  
  // Force refresh listening time (useful when app resumes)
  Future<void> refreshListeningTime() async {
    await _loadTodayListeningTime();
    if (_isSessionActive) {
      await _updateListeningTime();
    }
  }
  
  // Check if user can see ads (has listened for at least 10 minutes)
  bool canShowAds() {
    return _hasReached10Minutes;
  }
  
  // Get formatted listening time string
  String getFormattedListeningTime() {
    final hours = _todayListeningMinutes ~/ 60;
    final minutes = _todayListeningMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
  
  // Get progress towards 10-minute threshold (0.0 to 1.0)
  double getProgressTowardsAds() {
    return (_todayListeningMinutes / 10.0).clamp(0.0, 1.0);
  }
  
  // Get minutes remaining until ads are eligible
  int getMinutesUntilAds() {
    return (10 - _todayListeningMinutes).clamp(0, 10);
  }
  
  // Dispose resources
  @override
  void dispose() {
    _updateTimer?.cancel();
    _listeningTimeController.close();
    _adEligibilityController.close();
    super.dispose();
  }
} 