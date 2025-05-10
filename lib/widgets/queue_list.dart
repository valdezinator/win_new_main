import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/jam_session_service.dart';
import 'jam_session_controls.dart';
import 'join_session_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QueueList extends StatefulWidget {
  final Map<String, dynamic> currentSong;
  final VoidCallback onClose;
  final Function(Map<String, dynamic>)? onSongSelected;
  final String userName; // Added for jam session host name

  const QueueList({
    Key? key,
    required this.currentSong,
    required this.onClose,
    this.onSongSelected,
    this.userName = 'User', // Default value if not provided
  }) : super(key: key);

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
        child: Container(
          height: _songItemHeight,
          color: isHovered ? Theme.of(context).hoverColor.withOpacity(0.5) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 48,
                    height: 48,
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                        color: isCurrentSong ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: isCurrentSong ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      artist,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isCurrentSong)
                Icon(Icons.volume_up, color: Theme.of(context).colorScheme.primary, size: 20),
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


    return Padding( // Add padding around the Card for a floating effect
      padding: const EdgeInsets.all(8.0), // Adjust padding as needed
      child: Card(
        elevation: 8, // Add elevation for shadow
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // Rounded corners
        ),
        // Use a slightly transparent background to blend with the app theme
        // Consider using Theme.of(context).cardColor or a custom color
        color: Colors.grey[850]!.withOpacity(0.95), // Changed to a specific dark color
        clipBehavior: Clip.antiAlias, // Ensures content respects rounded corners
        child: SizedBox( // Constrain the width of the QueueList
          width: 350, // Adjust width as desired
          child: Column(
            mainAxisSize: MainAxisSize.min, // Important for Column in a Card
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [              Padding(
                padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 8.0, bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Queue',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white, // Changed to white
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white70), // Changed to white70 for slight dimming
                      onPressed: widget.onClose,
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),

              // Jam Session Controls
              if (!_isInJamSession) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                // Show Jam Session Controls for active session
                StreamBuilder<Map<String, dynamic>?>(
                  stream: _jamService.sessionStream,
                  initialData: _jamService.currentSession,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      final session = snapshot.data!;
                      final isHost = _jamService.isHost;

                      return JamSessionControls(
                        sessionId: session['id'],
                        sessionName: session['name'],
                        hostName: session['host_name'],
                        isHost: isHost,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    'Now Playing',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white70, // Changed to white70
                    ),
                  ),
                ),
                _buildSongItem(nowPlayingSong, true, hoveredIndex == nowPlayingSong['id'].hashCode, onTap: () {
                  if (widget.onSongSelected != null) {
                    widget.onSongSelected!(nowPlayingSong!);
                  }
                }),
                if (nextUpQueue.isNotEmpty)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],

              if (nextUpQueue.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    'Next Up',
                     style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white70, // Changed to white70
                    ),
                  ),
                ),
                Expanded( // Make the "Next Up" list scrollable
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: nextUpQueue.length,
                    itemBuilder: (context, index) {
                      final song = nextUpQueue[index];
                      return _buildSongItem(song, false, hoveredIndex == song['id'].hashCode, onTap: () {
                        if (widget.onSongSelected != null) {
                          widget.onSongSelected!(song);
                        }
                      });
                    },
                  ),
                ),
              ] else if (nowPlayingSong != null) ...[ // Show if only "Now Playing" is there
                Expanded( // Removed const
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'No songs up next.',
                        style: TextStyle(color: Colors.grey[300]), // Changed to a lighter grey
                      ),
                    ),
                  ),
                ),
              ],

              if (nowPlayingSong == null && nextUpQueue.isEmpty)
                Expanded( // Removed const
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Queue is empty.',
                        style: TextStyle(color: Colors.grey[300]), // Changed to a lighter grey
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}