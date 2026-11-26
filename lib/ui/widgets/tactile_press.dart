import 'package:flutter/material.dart';

/// Shared motion tokens following Emil Kowalski's design-engineering curves:
/// snappy ease-out for UI responses, subtle press scales, and reduced-motion support.
class AppMotion {
  static const Curve easeOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Curve easeInOut = Cubic(0.77, 0.0, 0.175, 1.0);

  static const Duration pressDuration = Duration(milliseconds: 120);
  static const Duration uiDuration = Duration(milliseconds: 180);
  static const Duration modalDuration = Duration(milliseconds: 220);
}

/// Provides immediate pointer-down scale feedback (`0.97`) and subtle hover state
/// while respecting platform reduced-motion settings.
class TactilePress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;

  const TactilePress({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.975,
    this.borderRadius,
  });

  @override
  State<TactilePress> createState() => _TactilePressState();
}

class _TactilePressState extends State<TactilePress> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final enabled = widget.onTap != null;
    final scale = (!reduceMotion && enabled && _isPressed) ? widget.pressedScale : 1.0;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: reduceMotion ? Duration.zero : AppMotion.pressDuration,
          curve: AppMotion.easeOut,
          child: AnimatedOpacity(
            opacity: enabled && _isHovered ? 0.96 : 1.0,
            duration: reduceMotion ? Duration.zero : AppMotion.pressDuration,
            curve: Curves.ease,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Subtle live indicator dot for active running processes.
class PulsingLiveDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingLiveDot({
    super.key,
    required this.color,
    this.size = 8,
  });

  @override
  State<PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<PulsingLiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final glow = 0.2 + (_controller.value * 0.35);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glow),
                blurRadius: 6,
                spreadRadius: 1.5,
              ),
            ],
          ),
        );
      },
    );
  }
}
