import 'package:flutter/material.dart';
import 'dart:math' as math;

class PlayingIndicator extends StatefulWidget {
  final bool isActive;
  final double barWidth;
  final double barGap;
  final double height;
  final Color color;

  const PlayingIndicator({
    super.key,
    required this.isActive,
    this.barWidth = 3,
    this.barGap = 2,
    this.height = 14,
    this.color = Colors.greenAccent,
  });

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return SizedBox(
        height: widget.height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (_) => Container(
            width: widget.barWidth,
            height: widget.height * 0.4,
            margin: EdgeInsets.only(right: widget.barGap),
            color: widget.color.withOpacity(0.35),
          )),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (i) {
              final progress = (_controller.value + (i * 0.2)) % 1.0;
              final h = (math.sin(progress * math.pi * 2) * 0.5 + 0.5) * widget.height;
              return Container(
                width: widget.barWidth,
                height: h.clamp(widget.height * 0.2, widget.height),
                margin: EdgeInsets.only(right: i == 3 ? 0 : widget.barGap),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
