import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class JamSessionService {
  static final JamSessionService _instance = JamSessionService._internal();
  factory JamSessionService() => _instance;

  JamSessionService._internal();

  final _supabase = Supabase.instance.client;
  final _uuid = const Uuid();

  // Stream controllers to broadcast changes to any listeners
  final _sessionController = StreamController<Map<String, dynamic>?>.broadcast();
  final _participantsController = StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<Map<String, dynamic>?> get sessionStream => _sessionController.stream;
  Stream<List<Map<String, dynamic>>> get participantsStream => _participantsController.stream;

  // Current session data
  Map<String, dynamic>? _currentSession;
  List<Map<String, dynamic>> _participants = [];
  String? _userId;
  RealtimeChannel? _sessionChannel;
  // Getters
  Map<String, dynamic>? get currentSession => _currentSession;
  List<Map<String, dynamic>> get participants => _participants;
  bool get isHost => _currentSession != null && _currentSession!['host_id'] == _userId;
  bool get isInSession => _currentSession != null;
  String? get sessionId => _currentSession?['id'];
  bool get isInitialized => _userId != null;
    // Initialize the service
  Future<void> initialize(String userId) async {
    _userId = userId;
    
    // Listen for auth state changes
    _supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedOut) {
        _userId = null;
        _currentSession = null;
        _sessionController.add(null);
      } else if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.userUpdated) {
        _userId = data.session?.user.id;
      }
    });
    
    await _restoreSession();
  }

  // Restore session from SharedPreferences (for app restart)
  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSessionId = prefs.getString('jam_session_id');
    
    if (savedSessionId != null) {
      try {
        await joinSession(savedSessionId);
      } catch (e) {
        // Session may have been deleted or expired
        await prefs.remove('jam_session_id');
      }
    }
  }
  // Create a new jam session
  Future<Map<String, dynamic>> createSession(Map<String, dynamic> songData, String hostName) async {
    // Get current user ID if not already set
    if (_userId == null) {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('Failed to start jam session: You must be signed in');
      }
      _userId = currentUser.id;
    }
    
    // Double check we have a user ID
    if (_userId == null) {
      throw Exception('User ID is not set');
    }

    // Prepare session data
    final sessionId = _uuid.v4();
    final sessionData = {
      'id': sessionId,
      'host_id': _userId!,
      'host_name': hostName,
      'current_song': songData['id'],
      'position_ms': 0,
      'current_position': 0,
      'allow_others_to_change_music': true,
      'participants': [_userId],
      'queue': songData['queue'] ?? [],
      'is_playing': false,
      'name': '$hostName\'s Jam'
    };

    // Insert into Supabase
    final response = await _supabase
        .from('jam_sessions')
        .insert(sessionData)
        .select()
        .single();

    // Add host as participant
    await _supabase.from('jam_session_participants').insert({
      'session_id': sessionId,
      'user_id': _userId,
      'joined_at': DateTime.now().toIso8601String(),
    });

    // Store session locally
    _currentSession = response;
    _sessionController.add(_currentSession);
    
    // Save to shared preferences for persistence
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jam_session_id', sessionId);

    // Subscribe to realtime updates
    _subscribeToSessionUpdates(sessionId);

    return response;
  }  // Join an existing session
  Future<Map<String, dynamic>> joinSession(String sessionId) async {
    // Get current user ID if not already set
    if (_userId == null) {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('Failed to join jam session: You must be signed in');
      }
      _userId = currentUser.id;
    }
    
    // Double check we have a user ID  
    if (_userId == null) {
      throw Exception('User ID is not set');
    }
    
    // Check if session is active
    final isActive = await checkSessionActive(sessionId);
    if (!isActive) {
      throw Exception('This jam session is no longer active or has expired.');
    }

    // Check if session exists
    final response = await _supabase
        .from('jam_sessions')
        .select()
        .eq('id', sessionId)
        .single();    // Add user as participant if not already
    if (_userId == null) throw Exception('User ID is not set');
    
    final existingParticipant = await _supabase
        .from('jam_session_participants')
        .select()
        .eq('session_id', sessionId)
        .eq('user_id', _userId!)
        .maybeSingle();

    if (existingParticipant == null) {
      await _supabase.from('jam_session_participants').insert({
        'session_id': sessionId,
        'user_id': _userId,
        'joined_at': DateTime.now().toIso8601String(),
      });

      // Update participants list in session
      List participants = response['participants'] ?? [];
      if (!participants.contains(_userId)) {
        participants.add(_userId);
        await _supabase
            .from('jam_sessions')
            .update({'participants': participants})
            .eq('id', sessionId);
      }
    }

    // Store session locally
    _currentSession = response;
    _sessionController.add(_currentSession);
    
    // Save to shared preferences for persistence
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jam_session_id', sessionId);

    // Subscribe to realtime updates
    _subscribeToSessionUpdates(sessionId);
    
    return response;
  }

  // End/leave session
  Future<void> endSession() async {
    if (_currentSession == null) return;
    
    final sessionId = _currentSession!['id'];
    
    // If host, delete the session
    if (isHost) {
      await _supabase.from('jam_sessions').delete().eq('id', sessionId);
      await _supabase.from('jam_session_participants').delete().eq('session_id', sessionId);
    } else {      // If participant, just remove from participants
      if (_userId != null) {
        await _supabase.from('jam_session_participants').delete()
            .eq('session_id', sessionId)
            .eq('user_id', _userId!);
      }
          
      // Update participants list in session
      List participants = _currentSession!['participants'] ?? [];
      if (participants.contains(_userId)) {
        participants.remove(_userId);
        await _supabase
            .from('jam_sessions')
            .update({'participants': participants})
            .eq('id', sessionId);
      }
    }

    // Clean up locally
    _sessionChannel?.unsubscribe();
    _sessionChannel = null;
    _currentSession = null;
    _participants = [];
    _sessionController.add(null);
    _participantsController.add([]);

    // Remove from shared preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jam_session_id');
  }
  // Update session playback state (for host)
  Future<void> updatePlaybackState({
    required String songId, 
    required int positionMs,
    required bool isPlaying,
    List<Map<String, dynamic>>? queue
  }) async {
    if (_currentSession == null || !isHost) return;

    final updateData = {
      'current_song': songId,
      'position_ms': positionMs,
      'is_playing': isPlaying,
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    if (queue != null) {
      updateData['queue'] = queue;
    }

    await _supabase
        .from('jam_sessions')
        .update(updateData)
        .eq('id', _currentSession!['id']);
  }
  
  // Update setting for allowing others to change music
  Future<void> updateAllowOthersToChangeMusic(bool allow) async {
    if (_currentSession == null || !isHost) return;
    
    await _supabase
        .from('jam_sessions')
        .update({
          'allow_others_to_change_music': allow,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', _currentSession!['id']);
  }

  // Copy session ID to clipboard
  Future<void> copySessionIdToClipboard() async {
    if (_currentSession == null) return;
    await Clipboard.setData(ClipboardData(text: _currentSession!['id']));
  }  // Subscribe to realtime updates for the session
  void _subscribeToSessionUpdates(String sessionId) {
    // Unsubscribe from any existing channels first
    _sessionChannel?.unsubscribe();
      // Create and subscribe to the channel
    _sessionChannel = _supabase
      .channel('jam_session_$sessionId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'jam_sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: sessionId,
        ),
        callback: (payload) {
          _currentSession = payload.newRecord;
          _sessionController.add(_currentSession);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'jam_sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: sessionId,
        ),
        callback: (payload) async {
          // Session was deleted (likely by host)
          if (!isHost) {
            await endSession();
          }
        },
      )
      .subscribe();
    
    // Fetch participants
    _fetchParticipants(sessionId);
  }

  // Fetch participants for a session
  Future<void> _fetchParticipants(String sessionId) async {
    final response = await _supabase
        .from('jam_session_participants')
        .select('user_id, joined_at')
        .eq('session_id', sessionId);
        
    _participants = List<Map<String, dynamic>>.from(response);
    _participantsController.add(_participants);
  }
  // Check if a session exists
  Future<bool> checkSessionExists(String sessionId) async {
    try {
      final response = await _supabase
          .from('jam_sessions')
          .select('id')
          .eq('id', sessionId)
          .maybeSingle();
      return response != null;
    } catch (e) {
      print('Error checking if session exists: $e');
      return false;
    }
  }  // Update session with current playback state (for host)
  Future<void> updateSessionPlayback(
    Map<String, dynamic> song,
    int positionMs,
    bool isPlaying
  ) async {
    if (_currentSession == null || !isHost) return;
    
    try {
      final updateData = {
        'current_song': song['id'],
        'position_ms': positionMs,
        'is_playing': isPlaying,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      // Update queue if it exists in the song
      if (song['queue'] != null && song['queue'] is List) {
        updateData['queue'] = song['queue'];
      }
      
      await _supabase
          .from('jam_sessions')
          .update(updateData)
          .eq('id', _currentSession!['id']);
    } catch (e) {
      print('Error updating jam session playback: $e');
      // If there's an exception with the session ID, try to recover the session
      if (e.toString().contains('not found') || e.toString().contains('does not exist')) {
        // Session might have been deleted
        _currentSession = null;
        _sessionController.add(null);
        
        // Remove from shared preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('jam_session_id');
      }
    }
  }
  // Placeholder for future networking optimizations
  // These methods were removed as they aren't needed for the current implementation
  // Check if a session is active and not expired
  Future<bool> checkSessionActive(String sessionId) async {
    try {
      final response = await _supabase
          .from('jam_sessions')
          .select('updated_at, created_at')
          .eq('id', sessionId)
          .maybeSingle();
          
      if (response == null) {
        return false; // Session doesn't exist
      }
      
      // Check if the session is older than 24 hours without updates
      final updatedAt = DateTime.parse(response['updated_at'] ?? response['created_at']);
      final now = DateTime.now();
      final difference = now.difference(updatedAt);
      
      // If session hasn't been active for 24 hours, consider it inactive
      return difference.inHours < 24;
    } catch (e) {
      print('Error checking session activity: $e');
      return false;
    }
  }

  // Clean up inactive sessions (admin function)
  Future<void> cleanupInactiveSessions() async {
    if (!isHost) return;
    
    try {
      // Get sessions older than 24 hours
      final yesterday = DateTime.now().subtract(const Duration(hours: 24));
      final response = await _supabase
          .from('jam_sessions')
          .select('id')
          .lt('updated_at', yesterday.toIso8601String());
          
      // Delete inactive sessions
      for (var session in response) {
        await _supabase.from('jam_sessions').delete().eq('id', session['id']);
        await _supabase.from('jam_session_participants').delete().eq('session_id', session['id']);
      }
    } catch (e) {
      print('Error cleaning up inactive sessions: $e');
    }
  }

  // Dispose resources
  void dispose() {
    _sessionChannel?.unsubscribe();
    _sessionController.close();
    _participantsController.close();
  }
}
