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

  // Playlist type constants
  static const String PLAYLIST_TYPE_DAYLIST = 'daylist';
  static const String PLAYLIST_TYPE_MOOD_MIX = 'mood_mix';
  static const String PLAYLIST_TYPE_FOCUS_FLOW = 'focus_flow';
  static const String PLAYLIST_TYPE_WORKOUT_MIX = 'workout_mix';
  static const String PLAYLIST_TYPE_CHILL_VIBES = 'chill_vibes';
  static const String PLAYLIST_TYPE_DISCOVERY_MIX = 'discovery_mix';
  static const String PLAYLIST_TYPE_THROWBACK_MIX = 'throwback_mix';
  static const String PLAYLIST_TYPE_PARTY_MIX = 'party_mix';
  static const String PLAYLIST_TYPE_SLEEP_MIX = 'sleep_mix';

  static const List<String> ALL_PLAYLIST_TYPES = [
    PLAYLIST_TYPE_DAYLIST,
    PLAYLIST_TYPE_MOOD_MIX,
    PLAYLIST_TYPE_FOCUS_FLOW,
    PLAYLIST_TYPE_WORKOUT_MIX,
    PLAYLIST_TYPE_CHILL_VIBES,
    PLAYLIST_TYPE_DISCOVERY_MIX,
    PLAYLIST_TYPE_THROWBACK_MIX,
    PLAYLIST_TYPE_PARTY_MIX,
    PLAYLIST_TYPE_SLEEP_MIX,
  ];

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

    if (user == null) return;

    // Generate initial playlists
    await _generateAllPlaylists();

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
      await _generateAllPlaylists();
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

  Future<void> _generateAllPlaylists() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Generate daylist first
      await _generatePlaylistByType(PLAYLIST_TYPE_DAYLIST);

      // Generate rewind playlist
      await _generatePlaylistByType('rewind');

      // Generate other playlist types using fallback
      for (final playlistType in ALL_PLAYLIST_TYPES) {
        if (playlistType != PLAYLIST_TYPE_DAYLIST && playlistType != 'rewind') {
          await _generatePlaylistByType(playlistType);
        }
      }
    } catch (e) {
      print('Error generating all playlists: $e');
    }
  }

  Future<Map<String, dynamic>?> _generatePlaylistByType(String playlistType) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Try to use database functions first
      try {
        if (playlistType == PLAYLIST_TYPE_DAYLIST) {
          final response = await _supabase.rpc(
            'generate_daylist',
            params: {
              'user_uuid': userId,
              'current_hour': DateTime.now().hour,
            },
          );

          if (response != null && (response as List).isNotEmpty) {
            return response[0];
          }
        } else if (playlistType == 'rewind') {
          final response = await _supabase.rpc(
            'generate_rewind',
            params: {
              'user_uuid': userId,
            },
          );

          if (response != null && (response as List).isNotEmpty) {
            return response[0];
          }
        }
      } catch (e) {
        print('Database function error for $playlistType: $e');
        // Continue to fallback if database function fails
      }

      // Use fallback for all playlist types
      return await _createFallbackPlaylist(playlistType);
    } catch (e) {
      print('Error generating playlist of type $playlistType: $e');
      return await _createFallbackPlaylist(playlistType);
    }
  }

  Future<Map<String, dynamic>?> _createFallbackPlaylist(String playlistType) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final currentHour = DateTime.now().hour;
      final timeOfDay = _getTimeOfDayCategory(currentHour);

      // Get playlist metadata based on type
      final playlistMetadata = _getPlaylistMetadata(playlistType, timeOfDay);

      // First check if we already have a dynamic playlist for this user and type
      try {
        final existingPlaylists = await _supabase
            .from('dynamic_playlists')
            .select()
            .eq('user_id', userId)
            .eq('playlist_type', playlistType);

        if ((existingPlaylists as List).isNotEmpty) {
          // Update the existing playlist
          final playlistId = existingPlaylists[0]['id'];

          // Update the playlist metadata
          await _supabase
              .from('dynamic_playlists')
              .update(playlistMetadata)
              .eq('id', playlistId);

          // Get songs for the playlist based on type
          final songs = await _getSongsForPlaylistType(playlistType);

          if (songs.isNotEmpty) {
            // Clear existing songs
            await _supabase
                .from('dynamic_playlist_songs')
                .delete()
                .eq('playlist_id', playlistId);

            // Add new songs with unique IDs
            for (var i = 0; i < songs.length; i++) {
              try {
                await _supabase
                    .from('dynamic_playlist_songs')
                    .insert({
                      'playlist_id': playlistId,
                      'song_id': songs[i]['id'],
                      'position': i + 1,
                    });
              } catch (e) {
                print('Error adding song ${songs[i]['id']} to playlist: $e');
                // Continue with next song if one fails
              }
            }
          }

          return existingPlaylists[0];
        }

        // Create a new playlist if none exists
        final response = await _supabase
            .from('dynamic_playlists')
            .insert({
              'user_id': userId,
              'playlist_type': playlistType,
              ...playlistMetadata,
            })
            .select();

        if ((response as List).isNotEmpty) {
          final playlistId = response[0]['id'];
          final songs = await _getSongsForPlaylistType(playlistType);

          if (songs.isNotEmpty) {
            // Add songs to the playlist with unique IDs
            for (var i = 0; i < songs.length; i++) {
              try {
                await _supabase
                    .from('dynamic_playlist_songs')
                    .insert({
                      'playlist_id': playlistId,
                      'song_id': songs[i]['id'],
                      'position': i + 1,
                    });
              } catch (e) {
                print('Error adding song ${songs[i]['id']} to playlist: $e');
                // Continue with next song if one fails
              }
            }
          }

          return response[0];
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

  Map<String, dynamic> _getPlaylistMetadata(String playlistType, String timeOfDay) {
    switch (playlistType) {
      case PLAYLIST_TYPE_DAYLIST:
        return {
          'name': '$timeOfDay Mix',
          'description': 'Your personalized mix for $timeOfDay vibes',
          'image_url': 'https://picsum.photos/200',
        };
      case PLAYLIST_TYPE_MOOD_MIX:
        return {
          'name': 'Mood Mix',
          'description': 'Songs that match your current mood',
          'image_url': 'https://picsum.photos/201',
        };
      case PLAYLIST_TYPE_FOCUS_FLOW:
        return {
          'name': 'Focus Flow',
          'description': 'Music to help you concentrate',
          'image_url': 'https://picsum.photos/202',
        };
      case PLAYLIST_TYPE_WORKOUT_MIX:
        return {
          'name': 'Workout Mix',
          'description': 'High-energy tracks for your workout',
          'image_url': 'https://picsum.photos/203',
        };
      case PLAYLIST_TYPE_CHILL_VIBES:
        return {
          'name': 'Chill Vibes',
          'description': 'Relaxing tunes for your downtime',
          'image_url': 'https://picsum.photos/204',
        };
      case PLAYLIST_TYPE_DISCOVERY_MIX:
        return {
          'name': 'Discovery Mix',
          'description': 'New music based on your taste',
          'image_url': 'https://picsum.photos/205',
        };
      case PLAYLIST_TYPE_THROWBACK_MIX:
        return {
          'name': 'Throwback Mix',
          'description': 'Your favorite songs from the past',
          'image_url': 'https://picsum.photos/206',
        };
      case PLAYLIST_TYPE_PARTY_MIX:
        return {
          'name': 'Party Mix',
          'description': 'High-energy tracks for your party',
          'image_url': 'https://picsum.photos/207',
        };
      case PLAYLIST_TYPE_SLEEP_MIX:
        return {
          'name': 'Sleep Mix',
          'description': 'Calming music to help you sleep',
          'image_url': 'https://picsum.photos/208',
        };
      default:
        return {
          'name': 'Unknown Mix',
          'description': 'A mix of songs',
          'image_url': 'https://picsum.photos/200',
        };
    }
  }

  Future<List<Map<String, dynamic>>> _getSongsForPlaylistType(String playlistType) async {
    try {
      var baseQuery = _supabase.from('songs_2').select('id');
      dynamic query;

      switch (playlistType) {
        case PLAYLIST_TYPE_MOOD_MIX:
          // Get songs with mood-related tags or high play count
          query = baseQuery.or('genre.ilike.%chill%,genre.ilike.%relax%')
              .order('play_count', ascending: false);
          break;
        case PLAYLIST_TYPE_FOCUS_FLOW:
          // Get instrumental or ambient songs or high play count
          query = baseQuery.or('genre.ilike.%instrumental%,genre.ilike.%ambient%')
              .order('play_count', ascending: false);
          break;
        case PLAYLIST_TYPE_WORKOUT_MIX:
          // Get high-energy songs or high play count
          query = baseQuery.or('genre.ilike.%dance%,genre.ilike.%electronic%')
              .order('play_count', ascending: false);
          break;
        case PLAYLIST_TYPE_CHILL_VIBES:
          // Get relaxing songs or high play count
          query = baseQuery.or('genre.ilike.%lofi%,genre.ilike.%ambient%')
              .order('play_count', ascending: false);
          break;
        case PLAYLIST_TYPE_DISCOVERY_MIX:
          // Get recently added songs
          query = baseQuery.order('created_at', ascending: false);
          break;
        case PLAYLIST_TYPE_THROWBACK_MIX:
          // Get older songs - using created_at instead of release_date
          query = baseQuery.order('created_at', ascending: true);
          break;
        case PLAYLIST_TYPE_PARTY_MIX:
          // Get party songs or high play count
          query = baseQuery.or('genre.ilike.%dance%,genre.ilike.%party%')
              .order('play_count', ascending: false);
          break;
        case PLAYLIST_TYPE_SLEEP_MIX:
          // Get sleep-friendly songs or high play count
          query = baseQuery.or('genre.ilike.%ambient%,genre.ilike.%lullaby%')
              .order('play_count', ascending: false);
          break;
        default:
          // For daylist, get a mix of songs
          query = baseQuery.order('play_count', ascending: false);
      }

      final response = await query.limit(20);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting songs for playlist type $playlistType: $e');
      return [];
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
      var result = await _generatePlaylistByType(PLAYLIST_TYPE_DAYLIST) ?? await _createFallbackPlaylist(PLAYLIST_TYPE_DAYLIST);

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
