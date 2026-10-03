import 'dart:math' as math;
import 'dart:ui';

class BoardViewportGeometry {
  static double fitScale(
    Size viewport,
    double boardSize, {
    required bool compact,
  }) {
    final paddingFactor = compact ? 1.0 : .94;
    return (math.min(viewport.width, viewport.height) *
            paddingFactor /
            boardSize)
        .clamp(.3, 4.0);
  }

  static bool canPan(Size viewport, double boardSize, double scale) {
    final extent = boardSize * scale;
    return extent > viewport.width + .5 || extent > viewport.height + .5;
  }

  static Offset constrainOffset(
    Size viewport,
    double boardSize,
    double scale,
    Offset offset,
  ) {
    final extent = boardSize * scale;
    double axis(double viewportExtent, double current) {
      if (extent <= viewportExtent + .5) return (viewportExtent - extent) / 2;
      return current.clamp(viewportExtent - extent, 0).toDouble();
    }

    return Offset(
      axis(viewport.width, offset.dx),
      axis(viewport.height, offset.dy),
    );
  }
}
