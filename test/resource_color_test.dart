import 'package:arcs_online/resource_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resource labels use the icon palette', () {
    expect(resourceColor('Fuel'), const Color(0xFFFFDE59));
    expect(resourceColor('Material'), const Color(0xFFD19BFF));
    expect(resourceColor('Weapon'), const Color(0xFFFF9A4A));
    expect(resourceColor('Relic'), const Color(0xFF77D8FF));
    expect(resourceColor('Psionic'), const Color(0xFFFF80D6));
  });
}
