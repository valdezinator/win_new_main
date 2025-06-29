import 'package:flutter/material.dart';
import '../services/ad_manager_service.dart';

class AdControls extends StatelessWidget {
  final AdManagerService _adManager = AdManagerService();

  AdControls({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: Stream.periodic(const Duration(milliseconds: 100))
          .map((_) => _adManager.isAdPlaying),
      initialData: false,
      builder: (context, snapshot) {
        final isAdPlaying = snapshot.data ?? false;
        
        if (!isAdPlaying) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4.0),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<bool>(
                stream: Stream.periodic(const Duration(milliseconds: 100))
                    .map((_) => _adManager.canSkip),
                initialData: false,
                builder: (context, snapshot) {
                  final canSkip = snapshot.data ?? false;
                  return TextButton(
                    onPressed: canSkip ? () => _adManager.skipAd() : null,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      canSkip ? 'Skip Ad' : 'Ad in Progress',
                      style: TextStyle(
                        fontSize: 12,
                        color: canSkip
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  );
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      // TODO: Implement volume control
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      // TODO: Show ad preferences dialog
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
} 