import 'dart:math' as math;
import 'dart:ui';

/// Places one ship of each color per round, preserving each player's piece order.
List<Map> clockwiseShips(Iterable<Map> pieces, Iterable<String> playerOrder) {
  final groups = <String, List<Map>>{};
  for (final piece in pieces) {
    if (piece['kind'] != 'ship') continue;
    groups.putIfAbsent('${piece['owner']}', () => []).add(piece);
  }
  final order = playerOrder.toList();
  final owners = [
    ...order.where(groups.containsKey),
    ...groups.keys.where((owner) => !order.contains(owner)),
  ];
  final result = <Map>[];
  final total = groups.values.fold<int>(0, (sum, ships) => sum + ships.length);
  var round = 0;
  while (result.length < total) {
    for (final owner in owners) {
      final ships = groups[owner]!;
      if (round < ships.length) result.add(ships[round]);
    }
    round++;
  }
  return result;
}

const double shipOrbitGap = 2;

double orbitAngularStep({
  required double radius,
  required double iconSize,
  double gap = shipOrbitGap,
}) => 2 * math.asin((iconSize + gap) / (2 * radius));

int orbitCapacity({
  required double radius,
  required double iconSize,
  double gap = shipOrbitGap,
}) =>
    (2 *
            math.pi /
            orbitAngularStep(radius: radius, iconSize: iconSize, gap: gap))
        .floor();

Offset orbitCenter(
  int index, {
  required double radius,
  required double iconSize,
  double gap = shipOrbitGap,
}) {
  final angle =
      -math.pi / 2 +
      index * orbitAngularStep(radius: radius, iconSize: iconSize, gap: gap);
  return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
}
