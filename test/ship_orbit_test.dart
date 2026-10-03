import 'package:arcs_online/ship_orbit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Map> ships(int red, int blue, [int yellow = 0]) => [
    for (var i = 0; i < red; i++) {'kind': 'ship', 'owner': 'red'},
    for (var i = 0; i < blue; i++) {'kind': 'ship', 'owner': 'blue'},
    for (var i = 0; i < yellow; i++) {'kind': 'ship', 'owner': 'yellow'},
  ];

  test("alternates colors until each player's ships are exhausted", () {
    expect(
      clockwiseShips(ships(2, 1), ['red', 'blue']).map((ship) => ship['owner']),
      ['red', 'blue', 'red'],
    );
    expect(
      clockwiseShips(ships(4, 2), ['red', 'blue']).map((ship) => ship['owner']),
      ['red', 'blue', 'red', 'blue', 'red', 'red'],
    );
    expect(
      clockwiseShips(ships(2, 2, 1), [
        'red',
        'blue',
        'yellow',
      ]).map((ship) => ship['owner']),
      ['red', 'blue', 'yellow', 'red', 'blue'],
    );
  });

  test('starts at twelve o’clock and packs ships clockwise near the top', () {
    final positions = [
      for (var i = 0; i < 3; i++) orbitCenter(i, radius: 56, iconSize: 18),
    ];
    expect(positions.first.dx, closeTo(0, .0001));
    expect(positions.first.dy, closeTo(-56, .0001));
    for (var i = 1; i < positions.length; i++) {
      expect(positions[i].dx, greaterThan(positions[i - 1].dx));
      expect(positions[i].dy, isNegative);
      expect(
        (positions[i] - positions[i - 1]).distance,
        closeTo(18 + shipOrbitGap, .0001),
      );
    }
  });

  test('capacity leaves enough room before wrapping back to the top', () {
    expect(orbitCapacity(radius: 56, iconSize: 18), 17);
  });
}
