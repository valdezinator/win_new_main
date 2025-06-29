import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:async';

class LyricsPanel extends StatefulWidget {
  final String? lyrics;
  final String? translatedLyrics;  // Add this line
  final VoidCallback onClose;
  final Duration currentPosition;
  final Duration totalDuration;
  final Color accentColor;

  const LyricsPanel({
    super.key,
    required this.lyrics,
    this.translatedLyrics,  // Add this line
    required this.onClose,
    required this.currentPosition,
    required this.totalDuration,
    required this.accentColor,
  });

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  late List<_LrcLine> _lrcLines;
  int _currentLine = 0;
  final ScrollController _scrollController = ScrollController();
  bool _isLrc = false;
  bool _showTranslation = false;  // Add this line

  @override
  void initState() {
    super.initState();
    _parseLyrics();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _parseLyrics();
    }
    if (oldWidget.currentPosition != widget.currentPosition) {
      _updateCurrentLine();
    }
  }
  void _parseLyrics() {
    _lrcLines = [];
    _isLrc = false;
    final lrc = widget.lyrics;
    if (lrc == null || lrc.trim().isEmpty) return;
    final lrcRegex = RegExp(r'^\[\d{2}:\d{2}\.\d{2,3}\]', multiLine: true);
    if (!lrcRegex.hasMatch(lrc)) return;
    _isLrc = true;
    final lineRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    
    // Parse the main lyrics
    final List<_LrcLine> tempLines = [];
    for (final line in lrc.split('\n')) {
      final match = lineRegex.firstMatch(line);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final ms = int.parse(match.group(3)!.padRight(3, '0'));
        final text = match.group(4)!.trim();
        final timestamp = Duration(minutes: min, seconds: sec, milliseconds: ms);
        tempLines.add(_LrcLine(timestamp, text));
      }
    }
    tempLines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Parse translated lyrics if available
    if (widget.translatedLyrics != null && widget.translatedLyrics!.isNotEmpty) {
      final List<String> translatedLines = widget.translatedLyrics!.split('\n');
      for (int i = 0; i < tempLines.length && i < translatedLines.length; i++) {
        tempLines[i].translatedText = translatedLines[i].trim();
      }
    }
    
    _lrcLines = tempLines;
  }

  void _updateCurrentLine() {
    if (!_isLrc || _lrcLines.isEmpty) return;
    final pos = widget.currentPosition;
    int idx = 0;
    for (int i = 0; i < _lrcLines.length; i++) {
      if (pos >= _lrcLines[i].timestamp) {
        idx = i;
      } else {
        break;
      }
    }
    if (_currentLine != idx) {
      setState(() {
        _currentLine = idx;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentLine();
      });
    }
  }

  void _scrollToCurrentLine() {
    if (!_scrollController.hasClients) return;
    
    final approximateLineHeight = 40.0; // Base height plus padding
    final targetOffset = (_currentLine * approximateLineHeight);
    final viewportHeight = _scrollController.position.viewportDimension;
    final offset = targetOffset - (viewportHeight / 3); // Center active line in viewport
    
    _scrollController.animateTo(
      offset < 0 ? 0 : offset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0), // Reduce height from the bottom
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Lyrics',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.translate,
                    color: _showTranslation ? widget.accentColor : Colors.white.withOpacity(0.7),
                  ),
                  tooltip: 'Show translation',
                  onPressed: () {
                    setState(() {
                      _showTranslation = !_showTranslation;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white.withOpacity(0.85)),
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Divider(
            color: Colors.white.withOpacity(0.1),
            height: 1,
          ),
          Expanded(
            child: _isLrc && _lrcLines.isNotEmpty
                ? ListView.builder(
                    controller: _scrollController,
                    itemCount: _lrcLines.length,
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    itemBuilder: (context, idx) {
                      final isActive = idx == _currentLine;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              style: GoogleFonts.inter(
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.7),
                                fontSize: isActive ? 18 : 15,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                height: 1.6,
                                letterSpacing: 0.2,
                                shadows: isActive
                                    ? [
                                        Shadow(
                                          color: widget.accentColor.withOpacity(0.5),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Text(
                                _lrcLines[idx].text,
                                textAlign: TextAlign.left,
                              ),
                            ),
                            if (_showTranslation && _lrcLines[idx].translatedText != null)
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                opacity: _showTranslation ? 1.0 : 0.0,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    _lrcLines[idx].translatedText!,
                                    style: GoogleFonts.inter(
                                      color: Colors.white.withOpacity(isActive ? 0.8 : 0.5),
                                      fontSize: isActive ? 14 : 12,
                                      height: 1.4,
                                      letterSpacing: 0.1,
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                    child: widget.lyrics != null && widget.lyrics!.trim().isNotEmpty
                        ? Text(
                            widget.lyrics!,
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
    );
  }
}

class _LrcLine {
  final Duration timestamp;
  final String text;
  String? translatedText;
  _LrcLine(this.timestamp, this.text, [this.translatedText]);
}
