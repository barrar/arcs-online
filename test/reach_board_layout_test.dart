import 'dart:math' as math;
import 'dart:ui';

import 'package:arcs_online/reach_board_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const setups = [
    ([2, 3, 4, 5], 2),
    ([1, 3, 4, 6], 2),
    ([1, 2, 3, 4, 5], 3),
    ([1, 2, 3, 4, 5, 6], 4),
  ];

  for (final compact in [false, true]) {
    for (final (clusters, playerCount) in setups) {
      test('$playerCount players, compact=$compact: planets have three ship '
          'widths of space and gates sit slightly farther apart', () {
        final layout = ReachBoardLayout(
          activeClusters: clusters,
          playerCount: playerCount,
          compact: compact,
        );
        final size = Size.square(layout.sceneSize);
        final gates = [
          for (final cluster in layout.activeClusters)
            layout.position('$cluster:gate', size),
        ];
        final planets = [
          for (final cluster in layout.activeClusters)
            for (final glyph in ['arrow', 'crescent', 'hex'])
              layout.position('$cluster:$glyph', size),
        ];
        final gateSpacing = (gates.first - gates[1]).distance;
        expect(gateSpacing, closeTo(ReachBoardLayout.gateSpacing, .001));
        expect(ReachBoardLayout.planetGap, ReachBoardLayout.shipIconSize * 3);
        expect(
          gateSpacing - ReachBoardLayout.planetSpacing,
          closeTo(ReachBoardLayout.shipIconSize, .001),
        );
        for (var index = 0; index < gates.length; index++) {
          expect(
            (gates[index] - gates[(index + 1) % gates.length]).distance,
            closeTo(gateSpacing, .001),
          );
        }
        for (var index = 0; index < planets.length; index++) {
          final nearest = [
            for (var other = 0; other < planets.length; other++)
              if (index != other) (planets[index] - planets[other]).distance,
          ].reduce(math.min);
          expect(nearest, closeTo(ReachBoardLayout.planetSpacing, .001));
        }
        for (final position in [...gates, ...planets]) {
          expect(position.dx, inInclusiveRange(65, layout.sceneSize - 65));
          expect(position.dy, inInclusiveRange(65, layout.sceneSize - 65));
        }
      });
    }
  }

  test('two-player map repeats its complete pattern under quarter turns', () {
    final layout = ReachBoardLayout(
      activeClusters: [2, 3, 4, 5],
      playerCount: 2,
      compact: true,
    );
    final size = Size.square(layout.sceneSize);
    final center = Offset(size.width / 2, size.height / 2);
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
  });

  test('phone map height tracks the space needed by each board', () {
    const phone = Size(390, 844);
    final two = ReachBoardLayout(
      activeClusters: [2, 3, 4, 5],
      playerCount: 2,
      compact: true,
    );
    final three = ReachBoardLayout(
      activeClusters: [1, 2, 3, 4, 5],
      playerCount: 3,
      compact: true,
    );
    final four = ReachBoardLayout(
      activeClusters: [1, 2, 3, 4, 5, 6],
      playerCount: 4,
      compact: true,
    );
    expect(two.compactViewportHeight(phone), 462);
    expect(three.compactViewportHeight(phone), greaterThan(462));
    expect(
      four.compactViewportHeight(phone),
      closeTo(phone.height * .76, .001),
    );
  });
}
