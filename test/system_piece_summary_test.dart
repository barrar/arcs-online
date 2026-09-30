import 'package:arcs_online/system_piece_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'groups fresh and damaged ships by owner and retains building owners',
    () {
      final summary = SystemPieceSummary.fromPieces([
        {'owner': 'red', 'kind': 'ship', 'damaged': false, 'id': 'a'},
        {'owner': 'red', 'kind': 'ship', 'damaged': true, 'id': 'b'},
        {'owner': 'red', 'kind': 'ship', 'damaged': false, 'id': 'c'},
        {'owner': 'blue', 'kind': 'ship', 'damaged': true, 'id': 'd'},
        {'owner': 'gold', 'kind': 'city', 'damaged': false, 'id': 'e'},
        {'owner': 'gold', 'kind': 'starport', 'damaged': false, 'id': 'f'},
      ]);

      expect(summary.shipsByOwner.keys, ['red', 'blue']);
      expect(summary.shipsByOwner['red']!.fresh, 2);
      expect(summary.shipsByOwner['red']!.damaged, 1);
      expect(summary.shipsByOwner['blue']!.fresh, 0);
      expect(summary.shipsByOwner['blue']!.damaged, 1);
      expect(summary.shipsByOwner.containsKey('gold'), isFalse);
      expect(summary.totalShips, 4);
      expect(summary.citiesByOwner['gold'], 1);
      expect(summary.starportsByOwner['gold'], 1);
      expect(summary.isEmpty, isFalse);
    },
  );

  test('empty system has no owners or pieces', () {
    final summary = SystemPieceSummary.fromPieces([]);
    expect(summary.shipsByOwner, isEmpty);
    expect(summary.citiesByOwner, isEmpty);
    expect(summary.starportsByOwner, isEmpty);
    expect(summary.isEmpty, isTrue);
  });
}
