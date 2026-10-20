import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared surface for the compact map and alarm dashboard.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent,
    this.glassOpacity,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final double? glassOpacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = BorderRadius.all(Radius.circular(24));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.22 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: scheme.surfaceContainerLow.withValues(
              alpha: glassOpacity ?? (dark ? 0.68 : 0.82),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: (accent ?? scheme.onSurface).withValues(
                  alpha: accent == null ? 0.27 : 0.58,
                ),
              ),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.onSurface.withValues(alpha: dark ? 0.09 : 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardLabel extends StatelessWidget {
  const DashboardLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color ?? scheme.primary,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );
  }
}
