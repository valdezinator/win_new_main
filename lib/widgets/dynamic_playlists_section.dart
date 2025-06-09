import 'package:flutter/material.dart';
import '../services/dynamic_playlist_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'daily_mix_card.dart';

class DynamicPlaylistsSection extends StatefulWidget {
  final Function(Map<String, dynamic>) onPlaylistSelected;

  const DynamicPlaylistsSection({
    super.key,
    required this.onPlaylistSelected,
  });

  @override
  State<DynamicPlaylistsSection> createState() => _DynamicPlaylistsSectionState();
}

class _DynamicPlaylistsSectionState extends State<DynamicPlaylistsSection> {
  final DynamicPlaylistService _playlistService = DynamicPlaylistService(
    Supabase.instance.client,
  );

  // Debug: Check authentication state
  void _checkAuthState() {
    final user = Supabase.instance.client.auth.currentUser;
    print('DynamicPlaylistsSection - Current user: ${user?.id}');
    print('DynamicPlaylistsSection - Is authenticated: ${user != null}');
  }

  @override
  void initState() {
    super.initState();
    _playlistService.initialize();
    _checkAuthState(); // Check authentication state
  }

  @override
  void dispose() {
    _playlistService.dispose();
    super.dispose();
  }

  // Method to refresh all dynamic playlists
  Future<void> _refreshAllPlaylists() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to refresh playlists'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final success = await _playlistService.refreshDaylist();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
            ? 'Playlists refreshed'
            : 'Failed to refresh playlists'),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Force rebuild to show the updated playlists
      setState(() {});
    }
  }

  String _getCurrentTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour <= 11) return 'Morning';
    if (hour >= 12 && hour <= 16) return 'Afternoon';
    if (hour >= 17 && hour <= 20) return 'Evening';
    return 'Night';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Daily Mix',
                style: GoogleFonts.montserrat(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w300,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _playlistService.isRefreshing,
                builder: (context, isRefreshing, child) {
                  return IconButton(
                    icon: isRefreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)
                        )
                      : const Icon(Icons.refresh, color: Colors.white),
                    tooltip: 'Refresh all playlists',
                    onPressed: isRefreshing ? null : _refreshAllPlaylists,
                  );
                }
              ),
            ],
          ),
        ),
        SizedBox(
          height: 290,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(DateTime.now().toString()), // Force rebuild on refresh
            future: _playlistService.getDynamicPlaylists(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final playlists = snapshot.data ?? [];

              if (playlists.isEmpty) {
                return const Center(child: Text('No dynamic playlists available'));
              }

              // Group playlists by type
              final Map<String, List<Map<String, dynamic>>> groupedPlaylists = {};
              for (final playlist in playlists) {
                final type = playlist['playlist_type'] as String? ?? 'unknown';
                if (!groupedPlaylists.containsKey(type)) {
                  groupedPlaylists[type] = [];
                }
                groupedPlaylists[type]!.add(playlist);
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: DynamicPlaylistService.ALL_PLAYLIST_TYPES.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, index) {
                  final playlistType = DynamicPlaylistService.ALL_PLAYLIST_TYPES[index];
                  final typePlaylists = groupedPlaylists[playlistType] ?? [];
                  
                  if (typePlaylists.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final playlist = typePlaylists.first;
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: DailyMixCard(
                      imageUrl: playlist['image_url'] ?? '',
                      title: _getPlaylistTitle(playlistType),
                      subtitle: playlist['name'] ?? 'Untitled Playlist',
                      description: playlist['description'] ?? _getPlaylistDescription(playlistType),
                      onTap: () {
                        final userId = Supabase.instance.client.auth.currentUser?.id;
                        if (userId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please sign in to view this playlist'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        widget.onPlaylistSelected(playlist);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _getPlaylistTitle(String playlistType) {
    switch (playlistType) {
      case DynamicPlaylistService.PLAYLIST_TYPE_DAYLIST:
        return _getCurrentTimeOfDay() + ' Mix';
      case DynamicPlaylistService.PLAYLIST_TYPE_MOOD_MIX:
        return 'Mood Mix';
      case DynamicPlaylistService.PLAYLIST_TYPE_FOCUS_FLOW:
        return 'Focus Flow';
      case DynamicPlaylistService.PLAYLIST_TYPE_WORKOUT_MIX:
        return 'Workout Mix';
      case DynamicPlaylistService.PLAYLIST_TYPE_CHILL_VIBES:
        return 'Chill Vibes';
      case DynamicPlaylistService.PLAYLIST_TYPE_DISCOVERY_MIX:
        return 'Discovery Mix';
      case DynamicPlaylistService.PLAYLIST_TYPE_THROWBACK_MIX:
        return 'Throwback Mix';
      case DynamicPlaylistService.PLAYLIST_TYPE_PARTY_MIX:
        return 'Party Mix';
      case DynamicPlaylistService.PLAYLIST_TYPE_SLEEP_MIX:
        return 'Sleep Mix';
      default:
        return 'Unknown Mix';
    }
  }

  String _getPlaylistDescription(String playlistType) {
    switch (playlistType) {
      case DynamicPlaylistService.PLAYLIST_TYPE_DAYLIST:
        return 'Your personalized mix for ${_getCurrentTimeOfDay()} vibes';
      case DynamicPlaylistService.PLAYLIST_TYPE_MOOD_MIX:
        return 'Songs that match your current mood';
      case DynamicPlaylistService.PLAYLIST_TYPE_FOCUS_FLOW:
        return 'Music to help you concentrate';
      case DynamicPlaylistService.PLAYLIST_TYPE_WORKOUT_MIX:
        return 'High-energy tracks for your workout';
      case DynamicPlaylistService.PLAYLIST_TYPE_CHILL_VIBES:
        return 'Relaxing tunes for your downtime';
      case DynamicPlaylistService.PLAYLIST_TYPE_DISCOVERY_MIX:
        return 'New music based on your taste';
      case DynamicPlaylistService.PLAYLIST_TYPE_THROWBACK_MIX:
        return 'Your favorite songs from the past';
      case DynamicPlaylistService.PLAYLIST_TYPE_PARTY_MIX:
        return 'High-energy tracks for your party';
      case DynamicPlaylistService.PLAYLIST_TYPE_SLEEP_MIX:
        return 'Calming music to help you sleep';
      default:
        return 'A mix of songs';
    }
  }
}
