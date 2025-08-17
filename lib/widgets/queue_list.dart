import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/jam_session_service.dart';
import 'jam_session_controls.dart';
import 'join_session_dialog.dart';

class QueueList extends StatefulWidget {
  final Map<String, dynamic> currentSong;
  final VoidCallback onClose;
  final Function(Map<String, dynamic>)? onSongSelected;
  final String userName; // Added for jam session host name
  final Function(List<Map<String, dynamic>>)? onQueueReordered; // NEW: callback for reordering

  const QueueList({
    super.key,
    required this.currentSong,
    required this.onClose,
    this.onSongSelected,
    this.userName = 'User', // Default value if not provided
    this.onQueueReordered, // NEW
  });

  @override
  _QueueListState createState() => _QueueListState();
}

class _QueueListState extends State<QueueList> {
  late ScrollController _scrollController;
  int? hoveredIndex;
  final JamSessionService _jamService = JamSessionService();
  final TextEditingController _sessionIdController = TextEditingController();
  bool _isInJamSession = false;
  bool _isJoining = false;

  // NEW: Define a fixed height for each song item
  final double _songItemHeight = 64.0; // Increased height for more content
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Check if already in a jam session
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Scroll to current song if there's a queue
      if (widget.currentSong['queue'] != null && (widget.currentSong['queue'] as List).isNotEmpty) {
        _scrollToCurrentSong();
      }

      // Check jam session status
      _isInJamSession = _jamService.isInSession;
      if (_isInJamSession) {
        setState(() {});
      }

      // Listen for jam session changes
      _jamService.sessionStream.listen((session) {
        if (mounted) {
          setState(() {
            _isInJamSession = session != null;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sessionIdController.dispose();
    super.dispose();
  }

  void _scrollToCurrentSong() {
    if (!_scrollController.hasClients || widget.currentSong['queue'] == null) return;

    final queue = List<Map<String, dynamic>>.from(widget.currentSong['queue'] ?? []);
    // The first song in the passed 'queue' from currentSong is the current playing one
    // if the queue is structured such that currentSong['queue'][0] is the current song.
    // Or, if currentSong itself is the current one, and queue is just upcoming.
    // Based on existing logic: queue = fullQueue.sublist(currentIndex)
    // So, the 0th index of *this* local `queue` variable is the current song.
    // We want to ensure this first item is visible if the list is long.
    // However, Spotify's queue usually shows "Now Playing" separately and "Next Up" scrolls.
    // Let's adjust scrolling based on the "Next Up" list.
    // For now, the existing logic scrolls the combined list, which is fine.

    final currentIndexInDisplayedQueue = queue.indexWhere((song) => song['id'] == widget.currentSong['id']);

    if (currentIndexInDisplayedQueue != -1) {
      // If "Now Playing" is a separate section, scrolling should apply to "Next Up"
      // For now, let's assume the current song (index 0 in `queue`) should be at the top.
      final scrollPosition = currentIndexInDisplayedQueue * _songItemHeight;
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
    // If the current song ID changes, or the queue itself changes reference or primary content
    if (widget.currentSong['id'] != oldWidget.currentSong['id'] ||
        widget.currentSong['queue'] != oldWidget.currentSong['queue']) {
      // Ensure scrolling happens after the build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.currentSong['queue'] != null && (widget.currentSong['queue'] as List).isNotEmpty) {
          _scrollToCurrentSong();
        }
      });
    }
  }

  Widget _buildSongItem(Map<String, dynamic> song, bool isCurrentSong, bool isHovered, {VoidCallback? onTap}) {
    final String title = song['title'] ?? 'Unknown Title';
    final String artist = song['artist'] ?? 'Unknown Artist';

    return MouseRegion(
      onEnter: (_) => setState(() => hoveredIndex = song['id'].hashCode),
      onExit: (_) => setState(() => hoveredIndex = null),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: _songItemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isCurrentSong
                ? Colors.green.withOpacity(0.15)
                : (isHovered ? Colors.white.withOpacity(0.04) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: isCurrentSong
                ? Border.all(color: Colors.green.withOpacity(0.4), width: 1)
                : null,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: song['image_url'] ?? '',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey[900],
                    child: Icon(Icons.music_note, color: Colors.white24),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey[900],
                    child: Icon(Icons.music_note, color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isCurrentSong ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: isCurrentSong ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      artist,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isCurrentSong)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.volume_up, color: Colors.green, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Start a new jam session
  Future<void> _startJamSession() async {
    try {
      setState(() {
        _isJoining = true;
      });

      await _jamService.createSession(widget.currentSong, widget.userName);

      setState(() {
        _isJoining = false;
        _isInJamSession = true;
      });
    } catch (e) {
      print('Error starting jam session: $e');
      setState(() {
        _isJoining = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start Jam Session')),
        );
      }
    }
  }

  // Join an existing jam session
  void _showJoinSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => JoinSessionDialog(
        onJoin: _joinSession,
      ),
    );
  }

  Future<void> _joinSession(String sessionId) async {
    try {
      setState(() {
        _isJoining = true;
      });

      await _jamService.joinSession(sessionId);

      setState(() {
        _isJoining = false;
        _isInJamSession = true;
      });
    } catch (e) {
      print('Error joining jam session: $e');
      setState(() {
        _isJoining = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to join Jam Session')),
        );
      }
    }
  }

  // End the current jam session
  Future<void> _endJamSession() async {
    try {
      await _jamService.endSession();
      setState(() {
        _isInJamSession = false;
      });
    } catch (e) {
      print('Error ending jam session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to end Jam Session')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullQueueFromWidget = List<Map<String, dynamic>>.from(widget.currentSong['queue'] ?? []);

    Map<String, dynamic>? nowPlayingSong;
    List<Map<String, dynamic>> nextUpQueue = [];

    if (fullQueueFromWidget.isNotEmpty) {
      final currentSongId = widget.currentSong['id'];
      int currentIndexInFullQueue = fullQueueFromWidget.indexWhere((s) => s['id'] == currentSongId);

      if (currentIndexInFullQueue != -1) {
        nowPlayingSong = fullQueueFromWidget[currentIndexInFullQueue];
        if (currentIndexInFullQueue + 1 < fullQueueFromWidget.length) {
          nextUpQueue = fullQueueFromWidget.sublist(currentIndexInFullQueue + 1);
        }
      } else if (fullQueueFromWidget.isNotEmpty) {
        // Fallback if currentSong['id'] is not in queue, take the first as now playing.
        // This case should ideally not happen if data is consistent.
        nowPlayingSong = fullQueueFromWidget[0];
        if (fullQueueFromWidget.length > 1) {
          nextUpQueue = fullQueueFromWidget.sublist(1);
        }
      }
    } else if (widget.currentSong['id'] != null) {
      // If nowPlayingSong is still null, but widget.currentSong has data (and no queue was passed or it was empty)
      // This could be the case if currentSong is just the song itself without a 'queue' field yet.
      nowPlayingSong = widget.currentSong;
      // nextUpQueue remains empty as no queue info was available beyond the current song.
    }


    // print('=== Queue List Debug ===');
    // print('Current song from widget: ${widget.currentSong['title']} (ID: ${widget.currentSong['id']})');
    // print('Full queue from widget: ${fullQueueFromWidget.map((s) => s['title']).toList()}');
    // print('Now Playing Song: ${nowPlayingSong != null ? nowPlayingSong['title'] : "null"}');
    // print('Next Up Queue: ${nextUpQueue.map((s) => s['title']).toList()}');


    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Container(
        width: 350,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1E24).withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 12)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(top: 14, left: 16, right: 4, bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.queue_music, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Queue', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: Colors.white54),
                    onPressed: widget.onClose,
                    tooltip: 'Close queue',
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),

            // Jam Session Controls / Active Session
            if (!_isInJamSession) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.headphones, size: 16),
                        label: const Text('Start a Jam'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _isJoining ? null : _startJamSession,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isJoining ? null : _showJoinSessionDialog,
                      child: const Text('Join'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ] else ...[
              StreamBuilder<Map<String, dynamic>?>(
                stream: _jamService.sessionStream,
                initialData: _jamService.currentSession,
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    final session = snapshot.data!;
                    return JamSessionControls(
                      sessionId: session['id'],
                      sessionName: session['name'],
                      hostName: session['host_name'],
                      isHost: _jamService.isHost,
                      onEnd: _endJamSession,
                    );
                  }
                  return const SizedBox();
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],

            if (nowPlayingSong != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Now Playing',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white60,
                      ),
                ),
              ),
              _buildSongItem(
                nowPlayingSong,
                true,
                hoveredIndex == nowPlayingSong['id'].hashCode,
                onTap: () => widget.onSongSelected?.call(nowPlayingSong!),
              ),
              if (nextUpQueue.isNotEmpty)
                const Divider(height: 1, color: Colors.white10, indent: 16, endIndent: 16),
            ],

            if (nextUpQueue.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Next Up',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white60,
                      ),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: nextUpQueue.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = nextUpQueue.removeAt(oldIndex);
                      nextUpQueue.insert(newIndex, item);
                      final fullQueue = [if (nowPlayingSong != null) nowPlayingSong, ...nextUpQueue];
                      widget.onQueueReordered?.call(fullQueue);
                    });
                  },
                  itemBuilder: (context, index) {
                    final song = nextUpQueue[index];
                    return ReorderableDragStartListener(
                      key: ValueKey(song['id'] ?? index),
                      index: index,
                      child: _buildSongItem(
                        song,
                        false,
                        hoveredIndex == song['id'].hashCode,
                        onTap: () => widget.onSongSelected?.call(song),
                      ),
                    );
                  },
                ),
              ),
            ] else if (nowPlayingSong != null) ...[
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: const Text('No songs up next.', style: TextStyle(color: Colors.white38)),
                  ),
                ),
              ),
            ],

            if (nowPlayingSong == null && nextUpQueue.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Queue is empty.', style: TextStyle(color: Colors.white38)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}