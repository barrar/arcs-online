/// Counts pieces at one system without exposing individual ship IDs to the UI.
class ShipCounts {
  const ShipCounts({this.fresh = 0, this.damaged = 0});

  final int fresh;
  final int damaged;
  int get total => fresh + damaged;
}

class SystemPieceSummary {
  SystemPieceSummary._(
    this.shipsByOwner,
    this.citiesByOwner,
    this.starportsByOwner,
  );

  final Map<String, ShipCounts> shipsByOwner;
  final Map<String, int> citiesByOwner;
  final Map<String, int> starportsByOwner;

  factory SystemPieceSummary.fromPieces(Iterable<Map> pieces) {
    final ships = <String, ShipCounts>{};
    final cities = <String, int>{};
    final starports = <String, int>{};
    for (final piece in pieces) {
      final owner = '${piece['owner']}';
      switch (piece['kind']) {
        case 'ship':
          final previous = ships[owner] ?? const ShipCounts();
          ships[owner] = ShipCounts(
            fresh: previous.fresh + (piece['damaged'] == true ? 0 : 1),
            damaged: previous.damaged + (piece['damaged'] == true ? 1 : 0),
          );
        case 'city':
          cities.update(owner, (count) => count + 1, ifAbsent: () => 1);
        case 'starport':
          starports.update(owner, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return SystemPieceSummary._(ships, cities, starports);
  }

  int get totalShips =>
      shipsByOwner.values.fold(0, (sum, ships) => sum + ships.total);
  int get totalCities =>
      citiesByOwner.values.fold(0, (sum, count) => sum + count);
  int get totalStarports =>
      starportsByOwner.values.fold(0, (sum, count) => sum + count);
  bool get isEmpty => totalShips + totalCities + totalStarports == 0;
}
