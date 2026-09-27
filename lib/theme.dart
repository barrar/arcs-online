import 'dart:math' as math;

import 'package:flutter/material.dart';

const voidBlack = Color(0xFF080D19);
const panel = Color(0xFF121D30);
const cyan = Color(0xFF7BE2EA);
const gold = Color(0xFFF7C87D);
const muted = Color(0xFF91A4BB);

ThemeData arcsTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: cyan,
    brightness: Brightness.dark,
    surface: panel,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: voidBlack,
    colorScheme: scheme,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 55,
        fontWeight: FontWeight.w900,
        letterSpacing: 5,
      ),
      headlineMedium: TextStyle(
        fontSize: 29,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45),
    ),
    cardTheme: CardThemeData(
      color: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF28394E)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: voidBlack,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0C1728),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
  );
}

class SpaceBackdrop extends StatelessWidget {
  const SpaceBackdrop({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-.6, -.55),
              radius: 1.5,
              colors: [Color(0xFF1C3151), voidBlack, Color(0xFF070B12)],
            ),
          ),
        ),
      ),
      const Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: StarfieldPainter())),
      ),
      child,
    ],
  );
}

class StarfieldPainter extends CustomPainter {
  const StarfieldPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(5071);
    for (var i = 0; i < 130; i++) {
      final point = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      final radius = i % 17 == 0 ? 1.6 : .5;
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = Colors.white.withValues(alpha: i % 9 == 0 ? .38 : .16),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(22),
    super.key,
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: panel.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF32455E)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}
