import 'package:arcs_online/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sixteen-point floor preserves larger text and accessibility scaling', () {
    const normal = MinimumTextScaler(TextScaler.noScaling);
    expect(normal.scale(9), 16);
    expect(normal.scale(16), 16);
    expect(normal.scale(24), 24);

    const enlarged = MinimumTextScaler(TextScaler.linear(1.5));
    expect(enlarged.scale(9), 24);
    expect(enlarged.scale(16), 24);
    expect(enlarged.scale(24), 36);
  });

  testWidgets('app wrapper applies the floor to nested text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: withReadableText,
      home: Builder(builder: (context) {
        final scaler = MediaQuery.textScalerOf(context);
        return Text('${scaler.scale(10)}');
      }),
    ));
    expect(find.text('16.0'), findsOneWidget);
  });
}
