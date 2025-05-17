import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';

class LyricsPanel extends StatelessWidget {
  final String? lyrics;
  final VoidCallback onClose;
  final Duration currentPosition;
  final Duration totalDuration;
  final Color accentColor;

  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.onClose,
    required this.currentPosition,
    required this.totalDuration,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    // Add detailed logging for lyrics panel
    debugPrint('LyricsPanel build called');
    debugPrint('Lyrics data received: ${lyrics != null ? 'Yes' : 'No'}');
    if (lyrics != null) {
      debugPrint('Lyrics length: ${lyrics!.length}');
      debugPrint('Lyrics preview: ${lyrics!.substring(0, lyrics!.length > 50 ? 50 : lyrics!.length)}...');
    } else {
      debugPrint('Lyrics is null');
    }    return Material(
      color: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.3, // 30% of screen width
        height: MediaQuery.of(context).size.height * 0.7, // 70% of screen height
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              // Backdrop blur effect
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: const Color(0xFF121212).withOpacity(0.9),
                ),
              ),

              // Content
              Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lyrics',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.white.withOpacity(0.8)),
                          onPressed: onClose,
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),

                  // Divider
                  Divider(
                    color: Colors.white.withOpacity(0.1),
                    height: 1,
                  ),

                  // Lyrics content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: lyrics != null
                        ? Text(
                            lyrics!,
                            style: GoogleFonts.inter(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              height: 1.5,
                              letterSpacing: 0.3,
                            ),
                          )
                        : Center(
                            child: Text(
                              'No lyrics available',
                              style: GoogleFonts.inter(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 14,
                              ),
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
