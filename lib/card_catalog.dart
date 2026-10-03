import 'dart:convert';

import 'package:flutter/services.dart';

class CourtCard {
  CourtCard(Map<String, dynamic> data)
    : id = data['id'] as String,
      name = data['name'] as String,
      type = data['type'] as String,
      suit = data['suit'] as String?,
      text = data['text'] as String;

  final String id;
  final String name;
  final String type;
  final String? suit;
  final String text;

  int? get raidCost {
    if (type != 'guild') return null;
    final number = int.parse(id.substring(id.length - 2));
    if (const {1, 7, 15, 19, 21}.contains(number)) return 3;
    if (const {22, 25}.contains(number)) return 1;
    return 2;
  }

  String get plainText => text.replaceAll(RegExp(r'\*+'), '').trim();
  String get artPath => 'assets/court_art/bc${id.substring(id.length - 2)}.jpg';
}

Future<List<CourtCard>> loadBaseCourt() async {
  final source = await rootBundle.loadString('assets/cards/base_court.json');
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  return (decoded['cards'] as List)
      .map((data) => CourtCard(data as Map<String, dynamic>))
      .toList();
}
