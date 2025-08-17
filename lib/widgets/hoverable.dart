import 'package:flutter/material.dart';

class Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovering) builder;
  final VoidCallback? onTap;
  final BorderRadius? radius;

  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.radius,
  });

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(context, _isHovering);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: widget.radius ?? BorderRadius.circular(8),
            boxShadow: _isHovering
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            scale: _isHovering ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 160),
            child: child,
          ),
        ),
      ),
    );
  }
}
