import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Check if an album is favorited by the current user
  Future<bool> isAlbumFavorited(String albumId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final response = await _supabase
          .from('user_favorites')
          .select('id')
          .eq('user_id', user.id)
          .eq('album_id', albumId)
          .single();

      return response != null;
    } catch (e) {
      // If no record found, it's not favorited
      return false;
    }
  }

  /// Toggle the favorite status of an album
  Future<bool> toggleAlbumFavorite(String albumId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Use the database function to toggle favorite status
      final response = await _supabase.rpc(
        'toggle_album_favorite',
        params: {
          'p_user_id': user.id,
          'p_album_id': albumId,
        },
      );

      return response as bool;
    } catch (e) {
      print('Error toggling album favorite: $e');
      rethrow;
    }
  }

  /// Get all favorited albums for the current user
  Future<List<Map<String, dynamic>>> getFavoritedAlbums() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      // First get the favorited album IDs
      final favoritesResponse = await _supabase
          .from('user_favorites')
          .select('album_id, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (favoritesResponse == null || favoritesResponse.isEmpty) {
        return [];
      }

      final favorites = List<Map<String, dynamic>>.from(favoritesResponse);
      final List<Map<String, dynamic>> favoritedAlbums = [];

      // For each favorited album ID, try to get the album data
      for (final favorite in favorites) {
        final albumId = favorite['album_id'];
        print('[FavoritesService] Looking up albumId: $albumId'); // DEBUG
        
        try {
          // Try to get album data from the albums table
          final albumResponse = await _supabase
              .from('albums')
              .select('*')
              .eq('id', albumId)
              .single();
          print('[FavoritesService] Query result for albumId $albumId: $albumResponse'); // DEBUG

          if (albumResponse != null) {
            final album = Map<String, dynamic>.from(albumResponse);
            favoritedAlbums.add({
              ...album,
              'favorited_at': favorite['created_at'],
            });
          }
        } catch (e) {
          print('[FavoritesService] Album not found for albumId $albumId, using placeholder. Error: $e'); // DEBUG
          // If album not found, use a consistent placeholder
          favoritedAlbums.add({
            'id': albumId,
            'title': 'Unknown Album',
            'artist': 'Unknown Artist',
            'image_url': null,
            'favorited_at': favorite['created_at'],
          });
        }
      }

      return favoritedAlbums;
    } catch (e) {
      print('Error getting favorited albums: $e');
      return [];
    }
  }

  /// Add an album to favorites
  Future<bool> addToFavorites(String albumId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _supabase
          .from('user_favorites')
          .insert({
            'user_id': user.id,
            'album_id': albumId,
          });

      return true;
    } catch (e) {
      print('Error adding album to favorites: $e');
      return false;
    }
  }

  /// Remove an album from favorites
  Future<bool> removeFromFavorites(String albumId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _supabase
          .from('user_favorites')
          .delete()
          .eq('user_id', user.id)
          .eq('album_id', albumId);

      return true;
    } catch (e) {
      print('Error removing album from favorites: $e');
      return false;
    }
  }
} 