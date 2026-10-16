import 'package:flutter/material.dart';

/// Keeps sheet actions reachable with a keyboard, large text or a short screen.
class ScrollableSheet extends StatelessWidget {
  const ScrollableSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    ),
  );
}
