import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../layouts/content_view.dart';

class RecommendedArtistsSection extends StatelessWidget {
  const RecommendedArtistsSection({super.key});

  Future<List<Map<String, dynamic>>> fetchArtists() async {
    try {
      final response = await Supabase.instance.client
          .from('artists')
          .select('name, image_url')
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Widget _buildArtistCircle(Map<String, dynamic> artist) {
    return GestureDetector(
      onTap: () {
        ContentViewController().navigateTo(
          ContentType.artist,
          data: artist,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(right: 24),
        child: Column(
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: artist['image_url'] ?? '',
                      width: 130,
                      height: 130,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[850],
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  ),
                  ClipOval(
                    child: Container(
                      width: 130,
                      height: 130,
                      color: Colors.black.withOpacity(0.2),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              artist['name'] ?? 'Unknown Artist',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
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
              'Recommended Artists',
              style: GoogleFonts.montserrat(
                fontSize: 22,
                fontWeight: FontWeight.w300,
                color: Colors.white,
              ),
            ),
            TextButton(
              onPressed: () {
                // Navigate to see all artists
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
        SizedBox(
          height: 180,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchArtists(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text(
                    'No artists found',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) => _buildArtistCircle(snapshot.data![index]),
              );
            },
          ),
        ),
      ],
    );
  }
} 