import 'package:flutter/material.dart';

/// A widget that displays a small indicator when adaptive features are active
class AdaptiveFeaturesIndicator extends StatelessWidget {
  final bool noiseAdaptiveActive;
  final bool routeCacheActive;

  const AdaptiveFeaturesIndicator({
    Key? key,
    required this.noiseAdaptiveActive,
    required this.routeCacheActive,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If neither feature is active, don't show anything
    if (!noiseAdaptiveActive && !routeCacheActive) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (noiseAdaptiveActive)
          _buildIndicator(
            Icons.mic,
            'Noise Adaptive Crossfade active',
            Colors.blueAccent,
          ),
        if (noiseAdaptiveActive && routeCacheActive)
          const SizedBox(width: 8),
        if (routeCacheActive)
          _buildIndicator(
            Icons.route,
            'Offline Route Cache active',
            Colors.greenAccent,
          ),
      ],
    );
  }

  Widget _buildIndicator(IconData icon, String tooltip, Color color) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              'Active',
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
