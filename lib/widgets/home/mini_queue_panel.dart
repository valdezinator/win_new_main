import 'package:flutter/material.dart';
import '../../services/audio_service.dart';

class MiniQueuePanel extends StatelessWidget {
  final List<Map<String, dynamic>> queue;
  final int currentIndex;
  final VoidCallback onClose;
  final void Function(Map<String, dynamic> song) onSelect;
  const MiniQueuePanel({super.key, required this.queue, required this.currentIndex, required this.onClose, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) {
      return _frame(Container(
        alignment: Alignment.center,
        child: const Text('Queue empty', style: TextStyle(color: Colors.grey)),
      ));
    }
    return _frame(ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: queue.length,
      separatorBuilder: (_, __) => const Divider(height: 8, color: Colors.white10),
      itemBuilder: (context, index) {
        final song = queue[index];
        final isCurrent = index == currentIndex;
        return InkWell(
          onTap: () => onSelect(song),
          borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isCurrent ? Colors.green.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (isCurrent)
                    const Icon(Icons.volume_up, size: 16, color: Colors.green)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      song['title'] ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    song['artist'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                    tooltip: 'Remove from queue',
                    onPressed: () {
                      AudioService().removeFromQueue(song['id'].toString());
                    },
                  ),
                ],
              ),
            ),
        );
      },
    ));
  }

  Widget _frame(Widget child) {
    return Container(
      width: 300,
      height: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E24).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.queue_music, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Up Next', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.clear, size: 18, color: Colors.white54),
                onPressed: onClose,
                tooltip: 'Close queue',
              )
            ],
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(child: child),
        ],
      ),
    );
  }
}
