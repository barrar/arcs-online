import 'dart:ui';

import 'package:arcs_online/reach_board_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(850, 850);
  const twoPlayerSetups = [
    [2, 3, 4, 5],
    [1, 3, 4, 6],
    [2, 3, 5, 6],
  ];

  test('two-player gates form a compact centered square for every setup', () {
    for (final clusters in twoPlayerSetups) {
      final layout = ReachBoardLayout(activeClusters: clusters, playerCount: 2);
      final gates = [
        for (final cluster in layout.activeClusters)
          layout.position('$cluster:gate', size),
      ];
      expect(gates, const [
        Offset(315, 315),
        Offset(535, 315),
        Offset(535, 535),
        Offset(315, 535),
      ]);
      for (var index = 0; index < gates.length; index++) {
        expect(
          (gates[index] - gates[(index + 1) % gates.length]).distance,
          220,
        );
      }
    }
  });

  test('the entire two-player node pattern repeats under quarter turns', () {
    final layout = ReachBoardLayout(
      activeClusters: [2, 3, 4, 5],
      playerCount: 2,
    );
    const center = Offset(425, 425);
    for (final glyph in ['gate', 'arrow', 'crescent', 'hex']) {
      for (var index = 0; index < 4; index++) {
        final current =
            layout.position('${layout.activeClusters[index]}:$glyph', size) -
            center;
        final next =
            layout.position(
              '${layout.activeClusters[(index + 1) % 4]}:$glyph',
              size,
            ) -
            center;
        expect(next, Offset(-current.dy, current.dx));
      }
    }
    final positions = [
      for (final cluster in layout.activeClusters)
        for (final glyph in ['gate', 'arrow', 'crescent', 'hex'])
          layout.position('$cluster:$glyph', size),
    ];
    for (var i = 0; i < positions.length; i++) {
      for (var j = i + 1; j < positions.length; j++) {
        expect((positions[i] - positions[j]).distance, greaterThan(88));
      }
    }
  });

  test('three-player board keeps its existing radial layout', () {
    final layout = ReachBoardLayout(
      activeClusters: [1, 2, 3, 4],
      playerCount: 3,
    );
    expect(layout.isTwoPlayerSquare, isFalse);
    expect(layout.position('1:gate', size), const Offset(425, 260));
  });

  test('compact phone board pulls systems inward without overlapping nodes', () {
    const phoneScene = Size(600, 600);
    for (final (clusters, count) in [
      ([2, 3, 4, 5], 2),
      ([1, 2, 3, 4, 5], 3),
      ([1, 2, 3, 4, 5, 6], 4),
    ]) {
      final regular = ReachBoardLayout(activeClusters: clusters, playerCount: count);
      final compact = ReachBoardLayout(activeClusters: clusters,
        playerCount: count, compact: true);
      final positions = <Offset>[];
      for (final cluster in clusters) {
        final gate = '$cluster:gate';
        final planet = '$cluster:arrow';
        expect((compact.position(gate, size) - compact.position(planet, size)).distance,
          lessThan((regular.position(gate, size) - regular.position(planet, size)).distance));
        for (final glyph in ['gate', 'arrow', 'crescent', 'hex']) {
          final id = '$cluster:$glyph';
          final point = compact.position(id, phoneScene);
          expect(point.dx, inInclusiveRange(44, 556));
          expect(point.dy, inInclusiveRange(44, 556));
          positions.add(point);
        }
      }
      for (var i = 0; i < positions.length; i++) {
        for (var j = i + 1; j < positions.length; j++) {
          expect((positions[i] - positions[j]).distance, greaterThanOrEqualTo(88));
        }
      }
    }
  });
}
