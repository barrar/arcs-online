import 'package:arcs_online/ambitions_panel.dart';
import 'package:arcs_online/resource_icon.dart';
import 'package:arcs_online/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the five ambition ranks match the base board', () {
    expect(
      baseAmbitions.map((ambition) => '${ambition.rank} ${ambition.name}'),
      ['2 Tycoon', '3 Tyrant', '4 Warlord', '5 Keeper', '6 Empath'],
    );
    expect(baseAmbitions.first.resources, ['Fuel', 'Material']);
    expect(baseAmbitions[1].counts, 'Captives');
    expect(baseAmbitions[2].counts, 'Trophies');
    expect(baseAmbitions[3].resources, ['Relic']);
    expect(baseAmbitions[4].resources, ['Psionic']);
  });

  testWidgets('all five ambitions remain visible before declaration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: arcsTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 360,
            child: AmbitionsPanel(markers: [], available: 3),
          ),
        ),
      ),
    );
    for (final ambition in baseAmbitions) {
      expect(find.text(ambition.name), findsOneWidget);
      expect(find.text('${ambition.rank}'), findsOneWidget);
    }
    expect(find.byType(ResourceIcon), findsNWidgets(4));
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('declared markers show combined first and second Power', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: arcsTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: AmbitionsPanel(
              available: 1,
              markers: const [
                {'ambition': 'tycoon', 'first': 5, 'second': 3},
                {'ambition': 'tycoon', 'first': 3, 'second': 1},
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('8/4'), findsOneWidget);
    expect(find.text('1 available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
