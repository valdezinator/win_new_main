import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/backblaze_service.dart';
import '../hoverable.dart';

class HitAlbumCard extends StatelessWidget {
  final Map<String, dynamic> album;
  final VoidCallback onTap;
  final BackblazeService backblazeService;
  const HitAlbumCard({super.key, required this.album, required this.onTap, required this.backblazeService});

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        return Container(
          width: 200,
            height: 250,
            margin: const EdgeInsets.only(right: 16),
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
                        color: Colors.black.withOpacity(hovering ? 0.4 : 0.2),
                        blurRadius: hovering ? 15 : 10,
                        offset: Offset(0, hovering ? 8 : 5),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FutureBuilder<String>(
                          future: backblazeService.getImageUrl(
                            album['image_url'],
                            album['file_identifier'],
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Container(color: Colors.grey[850], child: const Center(child: CircularProgressIndicator()));
                            }
                            if (snapshot.hasError || snapshot.data == null) {
                              return Container(color: Colors.grey[850], child: const Icon(Icons.error_outline, color: Colors.white54, size: 48));
                            }
                            return CachedNetworkImage(
                              imageUrl: snapshot.data!,
                              height: 200,
                              width: 200,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(color: Colors.grey[850], child: const Icon(Icons.album, color: Colors.white54, size: 48)),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: AnimatedOpacity(
                          opacity: hovering ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.black.withOpacity(0.6),
                            child: const Icon(Icons.play_arrow, color: Colors.white),
                          ),
                        ),
                      ),
                      if (album['downloaded'] == true)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green, width: 1),
                            ),
                            child: const Icon(Icons.download_done, color: Colors.green, size: 14),
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
                      SizedBox(
                        height: 20,
                        child: Text(
                          album['title'] ?? 'Unknown',
                          style: GoogleFonts.montserrat(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w300),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 16,
                        child: Text(
                          album['artist'] ?? 'Various Artists',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        );
      },
    );
  }
}
