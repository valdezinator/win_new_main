import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../hoverable.dart';
import '../playing_indicator.dart';

class QuickPlaySongCard extends StatelessWidget {
  final Map<String, dynamic> song;
  final bool isActive;
  final VoidCallback onTap;
  const QuickPlaySongCard({super.key, required this.song, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        return Container(
          width: 160,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? Colors.greenAccent.withOpacity(0.6) : Colors.grey[800]!, width: 1),
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
                      height: 160,
                      width: 160,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(height: 160, width: 160, color: Colors.grey[800]),
                      errorWidget: (context, url, error) => Container(height: 160, width: 160, color: Colors.grey[800], child: const Icon(Icons.error, color: Colors.white38)),
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              song['title'] ?? 'Unknown Title',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActive) const SizedBox(width: 4),
                          if (isActive) const PlayingIndicator(isActive: true, height: 14, barWidth: 3, barGap: 2),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song['artist'] ?? 'Unknown Artist',
                        style: TextStyle(color: Colors.grey[400], fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
