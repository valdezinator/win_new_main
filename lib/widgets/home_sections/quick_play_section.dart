import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuickPlaySection extends StatelessWidget {
  final Function(Map<String, dynamic>) onSongSelected;

  const QuickPlaySection({
    super.key,
    required this.onSongSelected,
  });

  Future<List<Map<String, dynamic>>> fetchSongs() async {
    try {
      final response = await Supabase.instance.client
          .from('songs_2')
          .select('id, title, artist, audio_url, image_url, duration')
          .order('created_at');

      if (response.isEmpty) {
        throw Exception('No data received from Supabase');
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching songs: $e');
      rethrow;
    }
  }

  Widget _buildQuickPlayCard(Map<String, dynamic> song) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onSongSelected(song),
        child: Container(
          width: 180,
          height: 250,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                child: Image.network(
                  song['image_url'] ?? '',
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 180,
                      height: 180,
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(Icons.music_note, color: Colors.white, size: 40),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 20,
                      child: Text(
                        song['title'] ?? 'Unknown Title',
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 1),
                    SizedBox(
                      height: 16,
                      child: Text(
                        song['artist'] ?? 'Unknown Artist',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Quick Play',
              style: GoogleFonts.montserrat(
                fontSize: 22,
                fontWeight: FontWeight.w300,
                color: Colors.white,
              ),
            ),
            TextButton(
              onPressed: () {
                // Navigate to see all quick play songs
              },
              child: Text(
                'See All',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[400],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: fetchSongs(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Error loading songs',
                  style: TextStyle(color: Colors.red),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                child: Text(
                  'No songs found',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            final songs = snapshot.data!;
            final displaySongs = songs.length > 8
                ? (songs..shuffle()).take(8).toList()
                : songs;

            return SizedBox(
              height: 230,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: displaySongs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _buildQuickPlayCard(displaySongs[index]),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
} 