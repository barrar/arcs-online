import 'package:flutter/material.dart';

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
