import 'dart:math' as math;
import 'dart:ui';

/// Presentation coordinates only. System IDs and game adjacency stay unchanged.
class ReachBoardLayout {
  ReachBoardLayout({
    required Iterable<int> activeClusters,
    required this.playerCount,
    this.compact = false,
  }) : activeClusters = activeClusters.toList()..sort();

  final List<int> activeClusters;
  final int playerCount;
  final bool compact;

  static const double planetDiameter = 92;
  static const double shipIconSize = 18;
  static const double shipOrbitRadius = 56;
  static const double shipCountOrbitRadius = 68;
  static const double shipCountBadgeWidth = 44;
  static const double shipCountBadgeHeight = 24;
  static const double planetGap = shipIconSize * 3;
  static const double gateExtraGap = shipIconSize;
  static const double planetSpacing = planetDiameter + planetGap;
  static const double gateSpacing = planetSpacing + gateExtraGap;
  static const double edgeMargin =
      shipCountOrbitRadius + shipCountBadgeHeight / 2;

  bool get isTwoPlayerSquare => playerCount == 2 && activeClusters.length == 4;

  double get sceneSize => isTwoPlayerSquare
      ? 3 * planetSpacing + 2 * edgeMargin
      : 2 * (_planetRadius + edgeMargin);

  double compactViewportHeight(Size viewport) => math.min(
    math.max(viewport.width, sceneSize * .65) + 72,
    math.min(viewport.height * .76, 700),
  );

  double get _planetRadius =>
      planetSpacing / (2 * math.sin(math.pi / (3 * activeClusters.length)));

  Offset position(String systemId, Size size) {
    final parts = systemId.split(':');
    final cluster = int.parse(parts.first);
    final glyph = parts.last;
    final center = Offset(size.width / 2, size.height / 2);
    final index = activeClusters.indexOf(cluster);
    if (index < 0) return center;
    if (isTwoPlayerSquare) {
      final gateHalf = gateSpacing / 2;
      final outer = 1.5 * planetSpacing;
      final inner = planetSpacing / 2;
      final local = switch (glyph) {
        'gate' => Offset(-gateHalf, -gateHalf),
        'arrow' => Offset(-outer, -inner),
        'crescent' => Offset(-outer, -outer),
        'hex' => Offset(-inner, -outer),
        _ => Offset.zero,
      };
      var rotated = local;
      for (var turn = 0; turn < index; turn++) {
        rotated = Offset(-rotated.dy, rotated.dx);
      }
      return center + rotated;
    }

    final clusters = activeClusters.length;
    final gateStep = 2 * math.pi / clusters;
    final planetStep = gateStep / 3;
    final gateRadius = gateSpacing / (2 * math.sin(gateStep / 2));
    final angle = -math.pi / 2 + index * gateStep;
    final offset = switch (glyph) {
      'arrow' => -planetStep,
      'hex' => planetStep,
      _ => 0.0,
    };
    final radius = glyph == 'gate' ? gateRadius : _planetRadius;
    return center +
        Offset(
          math.cos(angle + offset) * radius,
          math.sin(angle + offset) * radius,
        );
  }
}
