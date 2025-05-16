// Lyrics functionality commented out
// import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart';
//
// class LyricsPanel extends StatelessWidget {
//   final String? lyrics;
//   final VoidCallback onClose;
//   final Duration currentPosition;
//   final Duration totalDuration;
//   final Color accentColor;
//
//   const LyricsPanel({
//     super.key,
//     required this.lyrics,
//     required this.onClose,
//     required this.currentPosition,
//     required this.totalDuration,
//     required this.accentColor,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     // Add detailed logging for lyrics panel
//     debugPrint('LyricsPanel build called');
//     debugPrint('Lyrics data received: ${lyrics != null ? 'Yes' : 'No'}');
//     if (lyrics != null) {
//       debugPrint('Lyrics length: ${lyrics!.length}');
//       debugPrint('Lyrics preview: ${lyrics!.substring(0, lyrics!.length > 50 ? 50 : lyrics!.length)}...');
//     } else {
//       debugPrint('Lyrics is null');
//     }
//
//     return Material(
//       color: Colors.transparent,
//       child: Container(
//         width: 350,
//         height: MediaQuery.of(context).size.height * 0.6,
//         decoration: BoxDecoration(
//           color: const Color(0xFF121212),
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: Colors.white.withOpacity(0.2),
//             width: 1,
//           ),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.5),
//               blurRadius: 15,
//               spreadRadius: 5,
//             ),
//           ],
//         ),
//         child: Column(
//           children: [
//             // Header
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//               decoration: BoxDecoration(
//                 color: Colors.black,
//                 borderRadius: const BorderRadius.only(
//                   topLeft: Radius.circular(12),
//                   topRight: Radius.circular(12),
//                 ),
//                 border: Border(
//                   bottom: BorderSide(
//                     color: Colors.white.withOpacity(0.1),
//                   ),
//                 ),
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     'Lyrics',
//                     style: GoogleFonts.poppins(
//                       color: Colors.white,
//                       fontSize: 20,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                   IconButton(
//                     icon: const Icon(Icons.close, color: Colors.white, size: 24),
//                     onPressed: onClose,
//                     splashRadius: 20,
//                   ),
//                 ],
//               ),
//             ),
//
//             // Lyrics content
//             Expanded(
//               child: lyrics == null || lyrics!.isEmpty
//                   ? Center(
//                       child: Text(
//                         'No lyrics available for this song.',
//                         style: GoogleFonts.poppins(
//                           color: Colors.white,
//                           fontSize: 16,
//                         ),
//                       ),
//                     )
//                   : _buildLyricsContent(lyrics!),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildLyricsContent(String lyricsText) {
//     final lines = lyricsText.split('\n');
//     int highlightedLineIndex = 0;
//
//     if (totalDuration.inMilliseconds > 0) {
//       final progress = currentPosition.inMilliseconds / totalDuration.inMilliseconds;
//       highlightedLineIndex = (progress * lines.length).clamp(0, lines.length - 1).toInt();
//     }
//
//     return ListView.builder(
//       itemCount: lines.length,
//       padding: const EdgeInsets.all(16),
//       itemBuilder: (context, index) {
//         return Padding(
//           padding: const EdgeInsets.symmetric(vertical: 6.0),
//           child: Text(
//             lines[index],
//             style: TextStyle(
//               color: index == highlightedLineIndex
//                 ? accentColor
//                 : Colors.white,
//               fontWeight: index == highlightedLineIndex
//                 ? FontWeight.bold
//                 : FontWeight.normal,
//               fontSize: 16,
//             ),
//             textAlign: TextAlign.center,
//           ),
//         );
//       },
//     );
//   }
// }
