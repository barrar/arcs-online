import 'package:flutter/material.dart';

import 'resource_icon.dart';
import 'theme.dart';

class AmbitionDefinition {
  const AmbitionDefinition(
    this.id,
    this.rank,
    this.name, {
    this.resources = const [],
    this.pieceIcon,
    this.counts,
  });

  final String id;
  final int rank;
  final String name;
  final List<String> resources;
  final IconData? pieceIcon;
  final String? counts;
}

const baseAmbitions = <AmbitionDefinition>[
  AmbitionDefinition('tycoon', 2, 'Tycoon', resources: ['Fuel', 'Material']),
  AmbitionDefinition(
    'tyrant',
    3,
    'Tyrant',
    pieceIcon: Icons.link_rounded,
    counts: 'Captives',
  ),
  AmbitionDefinition(
    'warlord',
    4,
    'Warlord',
    pieceIcon: Icons.emoji_events_rounded,
    counts: 'Trophies',
  ),
  AmbitionDefinition('keeper', 5, 'Keeper', resources: ['Relic']),
  AmbitionDefinition('empath', 6, 'Empath', resources: ['Psionic']),
];

class AmbitionsPanel extends StatelessWidget {
  const AmbitionsPanel({
    required this.markers,
    required this.available,
    super.key,
  });

  final List<Map> markers;
  final int available;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'AMBITIONS',
                style: TextStyle(
                  color: gold,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
            Text('$available available', style: const TextStyle(color: muted)),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 300 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ambition in baseAmbitions)
                  SizedBox(
                    width: width,
                    child: _AmbitionTile(
                      ambition: ambition,
                      markers: markers
                          .where((marker) => marker['ambition'] == ambition.id)
                          .toList(),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _AmbitionTile extends StatelessWidget {
  const _AmbitionTile({required this.ambition, required this.markers});

  final AmbitionDefinition ambition;
  final List<Map> markers;

  @override
  Widget build(BuildContext context) {
    final description = ambition.counts ?? ambition.resources.join(' and ');
    final firstPower = markers.fold<int>(
      0,
      (sum, marker) => sum + (marker['first'] as int),
    );
    final secondPower = markers.fold<int>(
      0,
      (sum, marker) => sum + (marker['second'] as int),
    );
    final scoring = markers.isEmpty
        ? 'not declared'
        : '$firstPower first-place Power and $secondPower second-place Power';
    return Semantics(
      container: true,
      label: '${ambition.rank} ${ambition.name}, counts $description, $scoring',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1728),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: markers.isEmpty
                  ? cyan.withValues(alpha: .25)
                  : gold.withValues(alpha: .75),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 27,
                    height: 27,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${ambition.rank}',
                      style: const TextStyle(
                        color: gold,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      ambition.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final resource in ambition.resources) ...[
                    Tooltip(
                      message: resource,
                      child: ResourceIcon(
                        resource: resource,
                        size: 22,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (ambition.pieceIcon != null)
                    Tooltip(
                      message: ambition.counts!,
                      child: Icon(ambition.pieceIcon, color: gold, size: 22),
                    ),
                  Expanded(
                    child: Text(
                      markers.isEmpty ? '—' : '$firstPower/$secondPower',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: markers.isEmpty ? muted : gold,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
