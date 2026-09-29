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

  String get plainText => text.replaceAll(RegExp(r'\*+'), '').trim();
}

Future<List<CourtCard>> loadBaseCourt() async {
  final source = await rootBundle.loadString('assets/cards/base_court.json');
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  return (decoded['cards'] as List).map((data) => CourtCard(data as Map<String, dynamic>)).toList();
}
