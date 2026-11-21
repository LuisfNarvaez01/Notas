import 'package:flutter/material.dart';

ThemeData hilvaTheme(bool dark) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff4963d8),
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: dark ? const Color(0xff141923) : const Color(0xfffafbfe),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: scheme.surface,
    dividerColor: dark ? const Color(0xff2a3342) : const Color(0xffe3e7ef),
    textTheme: TextTheme(
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.6,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff1b2230) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark ? const Color(0xff354055) : const Color(0xffdde2ec),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      height: 72,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      centerTitle: false,
    ),
  );
}

class HilvaMark extends StatelessWidget {
  final double size;
  const HilvaMark({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _Mark(Theme.of(context).colorScheme.primary),
  );
}

class _Mark extends CustomPainter {
  final Color color;
  _Mark(this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = s.width * .15
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(s.width * .2, s.height * .17)
        ..lineTo(s.width * .2, s.height * .83)
        ..moveTo(s.width * .8, s.height * .17)
        ..lineTo(s.width * .8, s.height * .83)
        ..moveTo(s.width * .2, s.height * .65)
        ..cubicTo(
          s.width * .45,
          s.height * .65,
          s.width * .55,
          s.height * .35,
          s.width * .8,
          s.height * .35,
        ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Mark old) => old.color != color;
}
