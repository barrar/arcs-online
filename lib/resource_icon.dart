import 'package:flutter/material.dart';

Color resourceColor(String resource) => switch (resource.toLowerCase()) {
  'fuel' => const Color(0xFFFFDE59),
  'material' => const Color(0xFFD19BFF),
  'weapon' => const Color(0xFFFF9A4A),
  'relic' => const Color(0xFF77D8FF),
  'psionic' => const Color(0xFFFF80D6),
  _ => Colors.white,
};

/// Original artwork for the five base-game resource types.
class ResourceIcon extends StatelessWidget {
  const ResourceIcon({
    required this.resource,
    this.size = 20,
    this.excludeFromSemantics = false,
    super.key,
  });

  final String resource;
  final double size;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/resource_icons/arcs-resource-${resource.toLowerCase()}.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: '${resource.toLowerCase()} resource',
    excludeFromSemantics: excludeFromSemantics,
  );
}
