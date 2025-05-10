import 'package:flutter/material.dart';
import '../services/dynamic_playlist_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DynamicPlaylistsSection extends StatefulWidget {
  final Function(Map<String, dynamic>) onPlaylistSelected;

  const DynamicPlaylistsSection({
    Key? key,
    required this.onPlaylistSelected,
  }) : super(key: key);

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

  // Method to refresh the dynamic playlist
  Future<void> _refreshDynamicPlaylist() async {
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
            ? 'Playlist refreshed for ${_getCurrentTimeOfDay()}'
            : 'Failed to refresh playlist'),
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
                style: Theme.of(context).textTheme.titleLarge,
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
                    tooltip: 'Refresh for ${_getCurrentTimeOfDay()}',
                    onPressed: isRefreshing ? null : _refreshDynamicPlaylist,
                  );
                }
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
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

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: playlists.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      onTap: () {
                        // Check if user is logged in before navigating
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 140,
                              height: 140,
                              child: CachedNetworkImage(
                                imageUrl: playlist['image_url'] ?? '',
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[800],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.music_note),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 140,
                            child: Text(
                              playlist['name'] ?? 'Untitled Playlist',
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: Text(
                              playlist['description'] ?? '',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
}
