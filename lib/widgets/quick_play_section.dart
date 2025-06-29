import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

class QuickPlaySection extends StatefulWidget {
  final Function(Map<String, dynamic>) onSongSelected;

  const QuickPlaySection({
    super.key,
    required this.onSongSelected,
  });

  @override
  State<QuickPlaySection> createState() => _QuickPlaySectionState();
}

class _QuickPlaySectionState extends State<QuickPlaySection> {
  List<Map<String, dynamic>>? _songs;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      final response = await Supabase.instance.client
          .from('songs_2')
          .select('id, title, artist, audio_url, image_url, duration')
          .order('created_at');

      if (mounted) {
        setState(() {
          _songs = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
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
            // TextButton(
            //   onPressed: () {
            //     // Navigate to see all quick play songs
            //   },
            //   child: Text(
            //     'See All',
            //     style: TextStyle(
            //       fontSize: 14,
            //       color: Colors.grey[400],
            //     ),
            //   ),
            // ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Center(
            child: Text(
              'Error loading songs',
              style: TextStyle(color: Colors.red),
            ),
          )
        else if (_songs == null || _songs!.isEmpty)
          const Center(
            child: Text(
              'No songs found',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          SizedBox(
            height: 230,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _songs!.length > 8 ? 8 : _songs!.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _buildQuickPlayCard(_songs![index]),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildQuickPlayCard(Map<String, dynamic> song) {
    return GestureDetector(
      onTap: () => widget.onSongSelected(song),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: CachedNetworkImage(
                imageUrl: song['image_url'] ?? '',
                height: 160,
                width: 160,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[800],
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.error),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song['title'] ?? 'Unknown Title',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song['artist'] ?? 'Unknown Artist',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 