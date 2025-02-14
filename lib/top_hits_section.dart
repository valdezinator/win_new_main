import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TopHitsSection extends StatelessWidget {
  final List<Map<String, String>> topHits;

  const TopHitsSection({Key? key, required this.topHits}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (topHits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: topHits.length,
        itemBuilder: (context, index) {
          final hit = topHits[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: _buildTopHitItem(
              title: hit['title']!,
              artist: hit['artist']!,
              imageUrl: hit['imageUrl']!,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopHitItem({
    required String title,
    required String artist,
    required String imageUrl,
  }) {
    return MouseRegion(
      onEnter: (_) {
        // Add hover effect logic here if needed
      },
      onExit: (_) {
        // Add hover effect logic here if needed
      },
      child: Container(
        width: 150.0,
        height: 200.0,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.0),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
          ),
        ),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              title,
              style: GoogleFonts.raleway(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}