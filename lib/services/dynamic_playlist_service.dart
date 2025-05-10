import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class DynamicPlaylistService {
  final SupabaseClient _supabase;
  Timer? _dailyTimer;
  Timer? _weeklyTimer;
  Timer? _autoRefreshTimer;

  // Stream controller for refresh state
  final ValueNotifier<bool> isRefreshing = ValueNotifier<bool>(false);

  static const String _lastDailyUpdateKey = 'last_daily_playlist_update';
  static const String _lastWeeklyUpdateKey = 'last_weekly_playlist_update';
  static const int _autoRefreshInterval = 60; // Auto refresh check interval in minutes

  DynamicPlaylistService(this._supabase);

  // Timer for auto-refreshing playlists

  Future<void> initialize() async {
    // Debug: Check authentication state
    final user = _supabase.auth.currentUser;
    print('DynamicPlaylistService - Current user: ${user?.id}');
    print('DynamicPlaylistService - Is authenticated: ${user != null}');

    // Try to find the correct function name
    await _findCorrectPlaylistFunction();

    await _checkAndGeneratePlaylists();

    // Schedule daily playlists update
    _dailyTimer = Timer.periodic(const Duration(hours: 6), (_) {
      _checkAndGenerateDailyPlaylists();
    });

    // Schedule weekly playlists update
    _weeklyTimer = Timer.periodic(const Duration(hours: 24), (_) {
      _checkAndGenerateWeeklyPlaylists();
    });

    // Setup auto-refresh timer to check if playlist needs to be updated
    _setupAutoRefresh();
  }

  Future<void> _findCorrectPlaylistFunction() async {
    // Based on the SQL code, we know the correct functions to use:
    // 1. generate_all_dynamic_playlists - Main function to generate all playlists
    // 2. generate_daylist_song_ids - Function to get song IDs for daylist
    // We'll try these directly in the _generateDaylist method
  }

  void _setupAutoRefresh() {
    // Cancel any existing timer
    _autoRefreshTimer?.cancel();

    // Check every hour if we need to refresh the playlist based on time of day
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: _autoRefreshInterval), (_) {
      _checkTimeOfDayChange();
    });
  }

  Future<void> _checkTimeOfDayChange() async {
    final prefs = await SharedPreferences.getInstance();
    final lastHour = prefs.getInt('last_playlist_hour') ?? -1;
    final currentHour = DateTime.now().hour;

    // Get the time of day category for current and last hour
    final currentTimeOfDay = _getTimeOfDayCategory(currentHour);
    final lastTimeOfDay = _getTimeOfDayCategory(lastHour);

    // If time of day category has changed, refresh the playlist
    if (currentTimeOfDay != lastTimeOfDay) {
      print('Time of day changed from $lastTimeOfDay to $currentTimeOfDay. Refreshing playlist.');
      await refreshDaylist();
      await prefs.setInt('last_playlist_hour', currentHour);
    }
  }

  String _getTimeOfDayCategory(int hour) {
    if (hour >= 5 && hour <= 11) return 'Morning';
    if (hour >= 12 && hour <= 16) return 'Afternoon';
    if (hour >= 17 && hour <= 20) return 'Evening';
    return 'Night';
  }

  Future<void> _checkAndGeneratePlaylists() async {
    await _checkAndGenerateDailyPlaylists();
    await _checkAndGenerateWeeklyPlaylists();
  }

  Future<void> _checkAndGenerateDailyPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUpdate = prefs.getInt(_lastDailyUpdateKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - lastUpdate > 12 * 60 * 60 * 1000) { // 12 hours
      await _generateDaylist();
      await prefs.setInt(_lastDailyUpdateKey, now);
    }
  }

  Future<void> _checkAndGenerateWeeklyPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUpdate = prefs.getInt(_lastWeeklyUpdateKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - lastUpdate > 7 * 24 * 60 * 60 * 1000) { // 7 days
      await _generateRewind();
      await prefs.setInt(_lastWeeklyUpdateKey, now);
    }
  }

  Future<Map<String, dynamic>?> _generateDaylist() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final currentHour = DateTime.now().hour;

      // Based on the SQL code, we should use generate_all_dynamic_playlists
      try {
        // Call the main function to generate all dynamic playlists
        final response = await _supabase.rpc(
          'generate_all_dynamic_playlists',
          params: {
            'user_uuid': userId,
          },
        );

        // If successful, get the playlist that was created
        if (response != null) {
          // Get the daylist playlist
          final playlists = await _supabase
              .from('dynamic_playlists')
              .select()
              .eq('user_id', userId)
              .eq('playlist_type', 'daylist')
              .limit(1);

          if ((playlists as List).isNotEmpty) {
            return playlists[0];
          }
        }
        return null;
      } catch (e) {
        // Try the direct function for generating daylist songs
        try {
          final songIds = await _supabase.rpc(
            'generate_daylist_song_ids',
            params: {
              'user_uuid': userId,
              'current_hour': currentHour,
            },
          );

          // If we got song IDs, we need to update the playlist manually
          if (songIds != null) {
            // Get the existing daylist playlist
            final playlists = await _supabase
                .from('dynamic_playlists')
                .select()
                .eq('user_id', userId)
                .eq('playlist_type', 'daylist')
                .limit(1);

            if ((playlists as List).isNotEmpty) {
              final playlistId = playlists[0]['id'];

              // Clear existing songs
              await _supabase
                  .from('dynamic_playlist_songs')
                  .delete()
                  .eq('playlist_id', playlistId);

              // Add new songs
              if (songIds is List) {
                for (var i = 0; i < songIds.length; i++) {
                  await _supabase
                      .from('dynamic_playlist_songs')
                      .insert({
                        'playlist_id': playlistId,
                        'song_id': songIds[i],
                        'position': i + 1,
                      });
                }
              }

              // Update the playlist metadata
              final timeOfDay = _getTimeOfDayCategory(currentHour);
              await _supabase
                  .from('dynamic_playlists')
                  .update({
                    'name': '$timeOfDay Mix',
                    'description': 'Your personalized mix for $timeOfDay vibes',
                    // The last_updated column is automatically updated by the database
                  })
                  .eq('id', playlistId);

              return playlists[0];
            }
          }
        } catch (e2) {
          // Failed to generate using direct function
        }
      }

      // If all else fails, fall back to our manual method
      return null;
    } catch (e) {
      // Error in the main try block
      return null;
    }
  }

  /// Create a fallback playlist if the RPC functions fail
  Future<Map<String, dynamic>?> _createFallbackPlaylist() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final currentHour = DateTime.now().hour;
      final timeOfDay = _getTimeOfDayCategory(currentHour);

      print('Creating fallback playlist for $timeOfDay');

      // First check if we already have a dynamic playlist for this user
      try {
        final existingPlaylists = await _supabase
            .from('dynamic_playlists')
            .select()
            .eq('user_id', userId)
            .eq('playlist_type', 'daylist');

        if ((existingPlaylists as List).isNotEmpty) {
          // Update the existing playlist
          final playlistId = existingPlaylists[0]['id'];

          // Update the playlist metadata
          await _supabase
              .from('dynamic_playlists')
              .update({
                'name': '$timeOfDay Mix',
                'description': 'Your personalized mix for $timeOfDay vibes',
                // The last_updated column is automatically updated by the database
              })
              .eq('id', playlistId);

          // Get some songs for the playlist
          final songs = await _supabase
              .from('songs_2')
              .select('id')
              .limit(20);

          // Clear existing songs
          await _supabase
              .from('dynamic_playlist_songs')
              .delete()
              .eq('playlist_id', playlistId);

          // Add new songs
          for (var i = 0; i < (songs as List).length; i++) {
            await _supabase
                .from('dynamic_playlist_songs')
                .insert({
                  'playlist_id': playlistId,
                  'song_id': songs[i]['id'],
                  'position': i + 1,
                });
          }

          // Return the updated playlist
          return existingPlaylists[0];
        } else {
          // Create a new playlist
          final response = await _supabase
              .from('dynamic_playlists')
              .insert({
                'user_id': userId,
                'playlist_type': 'daylist',
                'name': '$timeOfDay Mix',
                'description': 'Your personalized mix for $timeOfDay vibes',
                'image_url': 'https://picsum.photos/200', // Placeholder image
              })
              .select();

          if ((response as List).isNotEmpty) {
            final playlistId = response[0]['id'];

            // Get some songs for the playlist
            final songs = await _supabase
                .from('songs_2')
                .select('id')
                .limit(20);

            // Add songs to the playlist
            for (var i = 0; i < (songs as List).length; i++) {
              await _supabase
                  .from('dynamic_playlist_songs')
                  .insert({
                    'playlist_id': playlistId,
                    'song_id': songs[i]['id'],
                    'position': i + 1,
                  });
            }

            return response[0];
          }
        }
      } catch (e) {
        print('Error in fallback playlist creation: $e');
      }

      return null;
    } catch (e) {
      print('Error creating fallback playlist: $e');
      return null;
    }
  }

  /// Manually refresh the daylist playlist based on current time of day
  Future<bool> refreshDaylist() async {
    try {
      isRefreshing.value = true;

      // Save current hour to preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_playlist_hour', DateTime.now().hour);

      // Try to generate new daylist using RPC functions, fall back to manual creation if needed
      var result = await _generateDaylist() ?? await _createFallbackPlaylist();

      // Force update the last update timestamp
      await prefs.setInt(_lastDailyUpdateKey, DateTime.now().millisecondsSinceEpoch);

      isRefreshing.value = false;
      return result != null;
    } catch (e) {
      isRefreshing.value = false;
      return false;
    }
  }

  Future<Map<String, dynamic>?> _generateRewind() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await _supabase.rpc(
      'generate_rewind',
      params: {
        'user_uuid': userId,
      },
    );

    return response as Map<String, dynamic>?;
  }

  Future<List<Map<String, dynamic>>> getDynamicPlaylists() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return [];
    }

    try {
      final response = await _supabase
          .from('dynamic_playlists')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getDynamicPlaylistByType(String playlistType) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('dynamic_playlists')
          .select()
          .eq('user_id', userId)
          .eq('playlist_type', playlistType)
          .single();

      return response;
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _dailyTimer?.cancel();
    _weeklyTimer?.cancel();
    _autoRefreshTimer?.cancel();
  }
}
