import 'package:flutter/material.dart';

/// Shared surface for the compact map and alarm dashboard.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: (accent ?? scheme.outlineVariant).withValues(
            alpha: accent == null ? 0.7 : 0.55,
          ),
        ),
      ),
      child: Padding(padding: padding, child: child),
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
