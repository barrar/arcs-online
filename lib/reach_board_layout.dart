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

  static const compactSquareScale = .8;

  bool get isTwoPlayerSquare => playerCount == 2 && activeClusters.length == 4;

  Offset position(String systemId, Size size) {
    final parts = systemId.split(':');
    final cluster = int.parse(parts.first);
    final glyph = parts.last;
    final center = Offset(size.width / 2, size.height / 2);
    if (isTwoPlayerSquare) {
      final corner = activeClusters.indexOf(cluster);
      if (corner >= 0) {
        // The four active clusters follow the same clockwise cycle used for
        // gate connections. Rotating one corner pattern keeps the board even.
        final local = switch (glyph) {
          'gate' => const Offset(-110, -110),
          'arrow' => const Offset(-290, -110),
          'crescent' => const Offset(-225, -225),
          'hex' => const Offset(-110, -290),
          _ => Offset.zero,
        };
        var rotated = local;
        for (var turn = 0; turn < corner; turn++) {
          rotated = Offset(-rotated.dy, rotated.dx);
        }
        return center + rotated * (compact ? compactSquareScale : 1.0);
      }
    }
    final angle = (-90 + (cluster - 1) * 60) * math.pi / 180;
    final offset = glyph == 'arrow'
        ? (compact ? -20.0 : -17.0)
        : glyph == 'hex'
        ? (compact ? 20.0 : 17.0)
        : 0.0;
    final radius = glyph == 'gate'
        ? (compact ? 130.0 : 165.0)
        : (compact ? 255.0 : 335.0);
    final theta = angle + offset * math.pi / 180;
    return center + Offset(math.cos(theta) * radius,
      math.sin(theta) * radius);
  }
}
