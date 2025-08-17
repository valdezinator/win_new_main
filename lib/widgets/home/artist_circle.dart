import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../hoverable.dart';
import '../../services/backblaze_service.dart';

class ArtistCircle extends StatelessWidget {
  final Map<String, dynamic> artist;
  final VoidCallback onTap;
  final BackblazeService backblazeService;
  const ArtistCircle({super.key, required this.artist, required this.onTap, required this.backblazeService});

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        return Container(
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
                      color: Colors.black.withOpacity(hovering ? 0.4 : 0.2),
                      blurRadius: hovering ? 15 : 10,
                      offset: Offset(0, hovering ? 8 : 5),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: FutureBuilder<String>(
                    future: backblazeService.getImageUrl(
                      artist['image_url'],
                      artist['file_identifier'],
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(color: Colors.grey[850], child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return Container(color: Colors.grey[850], child: const Icon(Icons.person, color: Colors.white54, size: 48));
                      }
                      return CachedNetworkImage(
                        imageUrl: snapshot.data!,
                        width: 130,
                        height: 130,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(color: Colors.grey[850], child: const Icon(Icons.person, color: Colors.white54, size: 48)),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                artist['name'] ?? 'Unknown Artist',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}
