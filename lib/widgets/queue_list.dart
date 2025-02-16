import 'package:flutter/material.dart';
import 'dart:ui';

class QueueList extends StatefulWidget {
  final Map<String, dynamic> currentSong;
  final VoidCallback onClose;

  const QueueList({
    Key? key,
    required this.currentSong,
    required this.onClose,
  }) : super(key: key);

  @override
  _QueueListState createState() => _QueueListState();
}

class _QueueListState extends State<QueueList> {
  late ScrollController _scrollController;
  int? hoveredIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentSong();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentSong() {
    if (!_scrollController.hasClients) return;
    
    final queue = List<Map<String, dynamic>>.from(widget.currentSong['queue'] ?? []);
    final currentIndex = queue.indexWhere((song) => song['id'] == widget.currentSong['id']);
    
    if (currentIndex != -1) {
      final scrollPosition = currentIndex * 56.0; // height of each item
      _scrollController.animateTo(
        scrollPosition,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void didUpdateWidget(QueueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSong['id'] != oldWidget.currentSong['id']) {
      _scrollToCurrentSong();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get full queue and find current index
    final fullQueue = List<Map<String, dynamic>>.from(widget.currentSong['queue'] ?? []);
    final currentIndex = fullQueue.indexWhere((song) => song['id'] == widget.currentSong['id']);
    
    // Create queue with only current and upcoming songs
    final queue = currentIndex != -1 
        ? fullQueue.sublist(currentIndex) 
        : fullQueue;

    print('=== Queue List Debug ===');
    print('Current song: ${widget.currentSong['title']}');
    print('Queue length: ${queue.length}');
    print('Queue contents: ${queue.map((s) => s['title']).toList()}');
    print('=======================');

    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        width: 400,
        height: 300,
        margin: const EdgeInsets.only(right: 16, bottom: 30), // Reduced from 100 to 90
        decoration: BoxDecoration(
          color: const Color(0xFF181818), // Solid background instead of transparent
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Queue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: widget.onClose,
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            // Queue list
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                itemCount: queue.length,
                itemBuilder: (context, index) {
                  final song = queue[index];
                  final isCurrentSong = index == 0; // First item is current song
                  final isHovered = index == hoveredIndex; // Fix: use hoveredIndex
                  
                  print('Queue item ${index}: ${song['title']}'); // Add debug print
                  
                  return MouseRegion(
                    onEnter: (_) => setState(() => hoveredIndex = index),
                    onExit: (_) => setState(() => hoveredIndex = null),
                    child: Container(
                      height: 56,
                      color: isHovered ? Colors.white.withOpacity(0.1) : Colors.transparent,
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            song['image_url'] ?? '',
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              color: Colors.grey[850],
                              child: const Icon(Icons.music_note, color: Colors.white54),
                            ),
                          ),
                        ),
                        title: Text(
                          song['title'] ?? 'Unknown',
                          style: TextStyle(
                            color: isCurrentSong ? Colors.green : Colors.white,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song['artist'] ?? 'Unknown Artist',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isCurrentSong
                          ? const Icon(Icons.volume_up, color: Colors.green, size: 16)
                          : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}