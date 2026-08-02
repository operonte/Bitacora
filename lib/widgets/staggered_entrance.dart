import 'package:flutter/material.dart';

/// Envuelve un ítem de lista con una entrada animada (fade + slide hacia
/// arriba), escalonada por [index]. Da sensación de vida a listas que antes
/// aparecían de golpe sin transición.
class StaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final delayMs = (index.clamp(0, 10) * 35);
    return TweenAnimationBuilder<double>(
      key: ValueKey('stagger_$index'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
