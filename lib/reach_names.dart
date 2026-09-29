// Player-facing names are assigned to the clusters in play. Official setup
// cards determine the underlying numbered clusters and their starting pieces.
class ReachNames {
  ReachNames(Iterable<int> activeClusters) {
    final active = activeClusters.toSet();
    final remaining = active.where((cluster) => !_corePreferred.containsValue(cluster)).toList()..sort();

    for (final region in _coreRegions) {
      final preferred = _corePreferred[region]!;
      if (active.contains(preferred)) _regions[preferred] = region;
    }
    for (final region in _coreRegions) {
      if (_regions.containsValue(region) || remaining.isEmpty) continue;
      _regions[remaining.removeAt(0)] = region;
    }
    for (final cluster in remaining) {
      _regions[cluster] = cluster == 3 ? 'Andromeda' : 'Sirius';
    }
  }

  static const _coreRegions = ['Vega', 'Sol', 'Canopus', 'Orion'];
  static const _corePreferred = {'Vega': 1, 'Sol': 5, 'Canopus': 4, 'Orion': 2};
  static const _planets = <String, Map<String, String>>{
    'Vega': {'arrow': 'Tatooine', 'crescent': 'Naboo', 'hex': 'Bespin'},
    'Sol': {'arrow': 'Uranus', 'crescent': 'Mars', 'hex': 'Earth'},
    'Canopus': {'arrow': 'Arrakis', 'crescent': 'Caladan', 'hex': 'Giedi Prime'},
    'Orion': {'arrow': 'Vulcan', 'crescent': 'Romulus', 'hex': 'Krypton'},
    'Andromeda': {'arrow': 'Xandar', 'crescent': 'Asgard', 'hex': 'Hala'},
    'Sirius': {'arrow': 'Gallifrey', 'crescent': 'Skaro', 'hex': 'Trenzalore'},
  };

  final Map<int, String> _regions = {};

  String system(String id) {
    final parts = id.split(':');
    if (parts.length != 2) return id;
    final cluster = int.tryParse(parts.first);
    final region = cluster == null ? null : _regions[cluster];
    if (region == null) return id;
    if (parts.last == 'gate') return '$region Gate';
    return _planets[region]?[parts.last] ?? id;
  }
}
