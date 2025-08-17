import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SectionContainer extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSeeAll;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;
  final bool showHeader;

  const SectionContainer({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.onSeeAll,
    this.padding = const EdgeInsets.only(bottom: 32.0),
    this.trailing,
  this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.montserrat(
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    child: const Text('See All'),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildState(),
          ),
        ],
      ),
    );
  }

  Widget _buildState() {
    if (isLoading) {
      return const Center(
        key: ValueKey('loading'),
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (error != null) {
      return Center(
        key: const ValueKey('error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error: $error',
              style: const TextStyle(color: Colors.redAccent),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      );
    }
    return child;
  }
}
