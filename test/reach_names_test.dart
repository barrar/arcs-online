import 'package:arcs_online/reach_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every printed base setup displays the four requested gate regions', () {
    const setups = <String, List<int>>{
      '2p-frontiers': [2, 3, 4, 5],
      '2p-mix-up-1': [1, 3, 4, 6],
      '2p-homelands': [2, 3, 5, 6],
      '2p-mix-up-2': [2, 3, 5, 6],
      '3p-mix-up': [2, 3, 5, 6],
      '3p-frontiers': [1, 4, 5, 6],
      '3p-homelands': [1, 2, 3, 4],
      '3p-core-conflict': [1, 2, 4, 5],
      '4p-mix-up-1': [1, 2, 4, 5, 6],
      '4p-mix-up-2': [1, 2, 3, 5, 6],
      '4p-frontiers': [1, 2, 3, 4, 6],
      '4p-mix-up-3': [1, 2, 3, 4, 5],
    };
    for (final entry in setups.entries) {
      final names = ReachNames(entry.value);
      final gates = [for (final cluster in entry.value) names.system('$cluster:gate')];
      expect(gates, containsAll(['Vega Gate', 'Sol Gate', 'Canopus Gate', 'Orion Gate']),
        reason: entry.key);
      expect(gates.toSet().length, entry.value.length, reason: entry.key);
      final sol = entry.value.singleWhere((cluster) => names.system('$cluster:gate') == 'Sol Gate');
      expect(names.system('$sol:hex'), 'Earth', reason: entry.key);
      expect(names.system('$sol:crescent'), 'Mars', reason: entry.key);
      expect(names.system('$sol:arrow'), 'Uranus', reason: entry.key);
      final canopus = entry.value.singleWhere((cluster) => names.system('$cluster:gate') == 'Canopus Gate');
      expect(names.system('$canopus:arrow'), 'Arrakis', reason: entry.key);
      expect(names.system('$canopus:crescent'), 'Caladan', reason: entry.key);
      expect(names.system('$canopus:hex'), 'Giedi Prime', reason: entry.key);
    }
  });

  test('retains familiar physical gate positions when they are in play', () {
    final names = ReachNames([1, 2, 4, 5, 6]);
    expect(names.system('1:gate'), 'Vega Gate');
    expect(names.system('5:gate'), 'Sol Gate');
    expect(names.system('4:gate'), 'Canopus Gate');
    expect(names.system('2:gate'), 'Orion Gate');
    expect(names.system('6:gate'), 'Sirius Gate');
  });
}
