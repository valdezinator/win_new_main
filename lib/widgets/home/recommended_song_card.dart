import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../hoverable.dart';
import '../playing_indicator.dart';

class RecommendedSongCard extends StatelessWidget {
  final Map<String, dynamic> song;
  final bool isActive;
  final VoidCallback onTap;
  const RecommendedSongCard({super.key, required this.song, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        return Container(
          width: 150,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? Colors.greenAccent.withOpacity(0.6) : Colors.grey[800]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: song['image_url'] ?? '',
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 150,
                        height: 150,
                        color: Colors.grey[850],
                        child: const Icon(Icons.music_note, color: Colors.white54, size: 40),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: AnimatedOpacity(
                        opacity: hovering || isActive ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.black.withOpacity(0.6),
                          child: Icon(isActive ? Icons.pause : Icons.play_arrow, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            song['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.montserrat(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isActive) const SizedBox(width: 4),
                        if (isActive) const PlayingIndicator(isActive: true, height: 14, barWidth: 3, barGap: 2),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song['artist'] ?? '',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
