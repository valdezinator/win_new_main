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
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4.0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Advertisement',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.0,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      // TODO: Implement ad close functionality
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StreamBuilder<bool>(
                    stream: Stream.periodic(const Duration(milliseconds: 100))
                        .map((_) => _adManager.canSkip),
                    initialData: false,
                    builder: (context, snapshot) {
                      final canSkip = snapshot.data ?? false;
                      return TextButton(
                        onPressed: canSkip ? () => _adManager.skipAd() : null,
                        child: Text(
                          canSkip ? 'Skip Ad' : 'Ad in Progress',
                          style: TextStyle(
                            color: canSkip
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.volume_up),
                        onPressed: () {
                          // TODO: Implement volume control
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: () {
                          // TODO: Show ad preferences dialog
                        },
                      ),
                    ],
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