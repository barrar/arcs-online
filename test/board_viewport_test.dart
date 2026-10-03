import 'dart:ui';

import 'package:arcs_online/board_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fully visible board stays centered and cannot pan', () {
    const viewport = Size(390, 462);
    final scale = BoardViewportGeometry.fitScale(viewport, 584, compact: true);
    expect(BoardViewportGeometry.canPan(viewport, 584, scale), isFalse);
    final offset = BoardViewportGeometry.constrainOffset(
      viewport,
      584,
      scale,
      const Offset(-200, 100),
    );
    expect(offset.dx, closeTo(0, .001));
    expect(offset.dy, closeTo(36, .001));
  });

  test('a zoomed board stops exactly where the visible content ends', () {
    const viewport = Size(400, 300);
    expect(BoardViewportGeometry.canPan(viewport, 500, 1), isTrue);
    expect(
      BoardViewportGeometry.constrainOffset(
        viewport,
        500,
        1,
        const Offset(-200, 80),
      ),
      const Offset(-100, 0),
    );
    expect(
      BoardViewportGeometry.constrainOffset(
        viewport,
        500,
        1,
        const Offset(90, -300),
      ),
      const Offset(0, -200),
    );
  });

  test('only an overflowing axis can pan', () {
    const viewport = Size(500, 300);
    expect(
      BoardViewportGeometry.constrainOffset(
        viewport,
        400,
        1,
        const Offset(-150, -150),
      ),
      const Offset(50, -100),
    );
  });
}
