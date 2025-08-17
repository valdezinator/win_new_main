import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.grey.shade800.withOpacity(0.3),
                Colors.grey.shade700.withOpacity(0.15),
                Colors.grey.shade800.withOpacity(0.3),
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SkeletonListHorizontal extends StatelessWidget {
  final int itemCount;
  final double itemWidth;
  final double itemHeight;
  final double spacing;

  const SkeletonListHorizontal({
    super.key,
    this.itemCount = 6,
    this.itemWidth = 160,
    this.itemHeight = 210,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (context, index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: itemWidth, height: itemWidth, borderRadius: BorderRadius.circular(8)),
              const SizedBox(height: 8),
              SkeletonBox(width: itemWidth * 0.9, height: 14, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 6),
              SkeletonBox(width: itemWidth * 0.6, height: 12, borderRadius: BorderRadius.circular(4)),
            ],
          );
        },
      ),
    );
  }
}

/// Skeleton list specialized for album cards (square covers + 2 lines)
class SkeletonAlbumListHorizontal extends StatelessWidget {
  final int itemCount;
  final double coverSize;
  final double spacing;
  const SkeletonAlbumListHorizontal({super.key, this.itemCount = 6, this.coverSize = 200, this.spacing = 16});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: coverSize + 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (context, index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: coverSize, height: coverSize, borderRadius: BorderRadius.circular(12)),
              const SizedBox(height: 8),
              SkeletonBox(width: coverSize * 0.9, height: 16, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 6),
              SkeletonBox(width: coverSize * 0.6, height: 14, borderRadius: BorderRadius.circular(4)),
            ],
          );
        },
      ),
    );
  }
}

/// Skeleton list for circular artist avatars
class SkeletonArtistCircleList extends StatelessWidget {
  final int itemCount;
  final double diameter;
  final double spacing;
  const SkeletonArtistCircleList({super.key, this.itemCount = 8, this.diameter = 130, this.spacing = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: diameter + 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (context, index) {
          return Column(
            children: [
              SkeletonBox(
                width: diameter,
                height: diameter,
                borderRadius: BorderRadius.circular(diameter),
              ),
              const SizedBox(height: 12),
              SkeletonBox(width: diameter * 0.7, height: 14, borderRadius: BorderRadius.circular(4)),
            ],
          );
        },
      ),
    );
  }
}
