import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewReleasesSection extends StatelessWidget {
  final Function(Map<String, dynamic>) onAlbumSelected;

  const NewReleasesSection({
    super.key,
    required this.onAlbumSelected,
  });

  Future<List<Map<String, dynamic>>> fetchNewReleases() async {
    try {
      final response = await Supabase.instance.client
          .from('new_releases')
          .select()
          .order('release_date', ascending: false);
      if (response.isEmpty) {
        throw Exception('No new releases found');
      }
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
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
              'New Releases',
              style: GoogleFonts.montserrat(
                fontSize: 22,
                fontWeight: FontWeight.w300,
                color: Colors.white,
              ),
            ),
            TextButton(
              onPressed: () {
                // Navigate to see all new releases
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
          height: 260,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchNewReleases(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final releases = snapshot.data ?? [];
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: releases.length,
                itemBuilder: (context, index) {
                  final release = releases[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: NewReleaseItem(
                      title: release['title'] ?? 'No Title',
                      artist: release['artist'] ?? 'Unknown Artist',
                      imageUrl: release['image_url'] ?? '',
                      onTap: () => onAlbumSelected(release),
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

class NewReleaseItem extends StatefulWidget {
  final String title;
  final String artist;
  final String imageUrl;
  final VoidCallback onTap;

  const NewReleaseItem({
    super.key,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  State<NewReleaseItem> createState() => _NewReleaseItemState();
}

class _NewReleaseItemState extends State<NewReleaseItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) => setState(() => _isHovering = true),
      onExit: (event) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: widget.imageUrl,
                        height: 200,
                        width: 200,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[850],
                          child: const Icon(Icons.album, color: Colors.white54, size: 48),
                        ),
                      ),
                    ),
                    if (_isHovering)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black.withOpacity(0.3),
                          ),
                          child: Center(
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.6),
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.artist,
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
      ),
    );
  }
} 