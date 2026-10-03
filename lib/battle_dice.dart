import 'package:flutter/material.dart';

import 'theme.dart';

const assaultDieColor = Color(0xFFAD3535);
const skirmishDieColor = Color(0xFF148FB1);
const raidDieColor = Color(0xFFB77921);

Color battleDieColor(String kind) => switch (kind) {
  'assault' => assaultDieColor,
  'skirmish' => skirmishDieColor,
  'raid' => raidDieColor,
  _ => muted,
};

class BattleDiceResult extends StatelessWidget {
  const BattleDiceResult({required this.faces, super.key});

  final List<Map> faces;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROLLED DICE · ${faces.length}',
          style: const TextStyle(
            color: gold,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        for (final kind in ['assault', 'skirmish', 'raid'])
          if (faces.any((face) => face['die'] == kind)) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                kind.toUpperCase(),
                style: TextStyle(
                  color: battleDieColor(kind),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final face in faces.where((face) => face['die'] == kind))
                  _BattleDieFace(face: face),
              ],
            ),
            const SizedBox(height: 10),
          ],
        const Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            _DieLegend(Icons.brightness_7, 'Ship hit'),
            _DieLegend(Icons.apartment, 'Building hit'),
            _DieLegend(Icons.local_fire_department, 'Own hit'),
            _DieLegend(Icons.key_rounded, 'Key'),
            _DieLegend(Icons.radio_button_unchecked, 'Intercept'),
          ],
        ),
      ],
    );
  }
}

class _BattleDieFace extends StatelessWidget {
  const _BattleDieFace({required this.face});

  final Map face;

  @override
  Widget build(BuildContext context) {
    final kind = '${face['die']}';
    final own = face['own'] as int;
    final ships = face['ship'] as int;
    final buildings = face['building'] as int;
    final keys = face['keys'] as int;
    final intercept = face['intercept'] == true;
    final descriptions = <String>[
      if (own > 0) '$own hit${own == 1 ? '' : 's'} to your ships',
      if (intercept) 'intercept',
      if (ships > 0) '$ships hit${ships == 1 ? '' : 's'} to defending ships',
      if (buildings > 0)
        '$buildings hit${buildings == 1 ? '' : 's'} to defending buildings',
      if (keys > 0) '$keys raid key${keys == 1 ? '' : 's'}',
    ];
    final label =
        '$kind die: ${descriptions.isEmpty ? 'blank' : descriptions.join(', ')}';
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: battleDieColor(kind),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Colors.white.withValues(alpha: .55)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ExcludeSemantics(
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 1,
              runSpacing: 1,
              children: [
                for (var i = 0; i < own; i++)
                  const Icon(
                    Icons.local_fire_department,
                    color: Colors.white,
                    size: 16,
                  ),
                if (intercept)
                  const Icon(
                    Icons.radio_button_unchecked,
                    color: Colors.white,
                    size: 16,
                  ),
                for (var i = 0; i < ships; i++)
                  const Icon(Icons.brightness_7, color: Colors.white, size: 16),
                for (var i = 0; i < buildings; i++)
                  const Icon(Icons.apartment, color: Colors.white, size: 16),
                for (var i = 0; i < keys; i++)
                  const Icon(Icons.key_rounded, color: Colors.white, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DieLegend extends StatelessWidget {
  const _DieLegend(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Colors.white, size: 17),
      const SizedBox(width: 3),
      Text(label, style: const TextStyle(color: muted)),
    ],
  );
}
