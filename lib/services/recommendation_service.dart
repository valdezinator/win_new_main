import 'package:supabase_flutter/supabase_flutter.dart';

class RecommendationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get recommended songs for the current user
  Future<List<Map<String, dynamic>>> getRecommendedSongs(String userId) async {
    // 1. Get recently played songs (last 10)
    final recent = await _supabase
        .from('user_listening_sessions')
        .select('song_id')
        .eq('user_id', userId)
        .order('start_time', ascending: false)
        .limit(10);
    List<String> recentSongIds = recent.map<String>((e) => e['song_id'] as String).toList();

    // 2. Get genres and artists of recently played songs
    List<Map<String, dynamic>> recentSongs = [];
    if (recentSongIds.isNotEmpty) {
      recentSongs = await _supabase
        .from('songs_2')
        .select('id, genre, artist')
        .inFilter('id', recentSongIds);
    }
    final recentGenres = <String>{};
    final recentArtists = <String>{};
    for (var song in recentSongs) {
      if (song['genre'] != null) {
        for (var genre in song['genre'].toString().split(',')) {
          recentGenres.add(genre.trim());
        }
      }
      if (song['artist'] != null) {
        recentArtists.add(song['artist'].toString().trim());
      }
    }

    // 3. Recommend songs by similar genre/artist, excluding already played
    List<Map<String, dynamic>> similar = [];
    if (recentGenres.isNotEmpty || recentArtists.isNotEmpty) {
      final genreFilter = recentGenres.isNotEmpty ? _supabase.from('songs_2').select().inFilter('genre', recentGenres.toList()) : null;
      final artistFilter = recentArtists.isNotEmpty ? _supabase.from('songs_2').select().inFilter('artist', recentArtists.toList()) : null;
      List<Map<String, dynamic>> genreSongs = [];
      List<Map<String, dynamic>> artistSongs = [];
      if (genreFilter != null) {
        genreSongs = await genreFilter;
      }
      if (artistFilter != null) {
        artistSongs = await artistFilter;
      }
      similar = [...genreSongs, ...artistSongs];
      // Remove songs already played
      similar = similar.where((song) => !recentSongIds.contains(song['id'])).toList();
    }

    // 4. Fallback: Get popular songs
    final popular = await _supabase
        .from('songs_2')
        .select()
        .order('play_count', ascending: false)
        .limit(20);

    // TODO: Add collaborative filtering/ML-based recommendations
    // For now, return a mix of similar and popular
    final all = [...similar, ...popular];
    final seen = <String>{};
    final deduped = all.where((song) => seen.add(song['id'])).toList();
    return deduped.take(20).toList();
  }

  // Get similar artists for a user
  Future<List<Map<String, dynamic>>> getSimilarArtists(String userId) async {
    // TODO: Implement using listening history and artist similarity
    return [];
  }
} 