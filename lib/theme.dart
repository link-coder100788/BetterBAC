import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'src/rust/api/types.dart';

/// Duolingo-inspired palette. Each colour has a darker "lip" shade used for
/// the 3D bottom edge of buttons and cards.
class Palette {
  static const green = Color(0xFF58CC02);
  static const greenLip = Color(0xFF58A700);
  static const blue = Color(0xFF1CB0F6);
  static const blueLip = Color(0xFF1899D6);
  static const orange = Color(0xFFFF9600);
  static const orangeLip = Color(0xFFE08600);
  static const red = Color(0xFFFF4B4B);
  static const redLip = Color(0xFFEA2B2B);
  static const yellow = Color(0xFFFFC800);
  static const yellowLip = Color(0xFFE5B400);
  static const purple = Color(0xFFCE82FF);
  static const purpleLip = Color(0xFFA568CC);

  static const ink = Color(0xFF4B4B4B);
  static const muted = Color(0xFF777777);
  static const gray = Color(0xFFAFAFAF);
  static const line = Color(0xFFE5E5E5);
  static const snow = Color(0xFFF7F7F7);
  static const white = Colors.white;
}

Color strandColor(Strand s) => switch (s) {
  Strand.creativity => Palette.purple,
  Strand.activity => Palette.orange,
  Strand.service => Palette.blue,
};

Color strandLip(Strand s) => switch (s) {
  Strand.creativity => Palette.purpleLip,
  Strand.activity => Palette.orangeLip,
  Strand.service => Palette.blueLip,
};

IconData strandIcon(Strand s) => switch (s) {
  Strand.creativity => Icons.palette_rounded,
  Strand.activity => Icons.directions_run_rounded,
  Strand.service => Icons.volunteer_activism_rounded,
};

Color categoryColor(EventCategory c) => switch (c) {
  EventCategory.cas => Palette.green,
  EventCategory.extendedEssay => Palette.purple,
  EventCategory.tok => Palette.blue,
  EventCategory.internalAssessment => Palette.orange,
  EventCategory.exam => Palette.red,
  EventCategory.homework => Palette.yellow,
  EventCategory.other => Palette.gray,
};

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.green,
      primary: Palette.green,
      secondary: Palette.blue,
      error: Palette.red,
      surface: Palette.white,
    ),
    scaffoldBackgroundColor: Palette.white,
    // google_fonts 9 builds on package:material_ui, so only share the family
    // name rather than its TextTheme type.
    fontFamily: GoogleFonts.nunito().fontFamily,
  );
  final text = base.textTheme.apply(
    bodyColor: Palette.ink,
    displayColor: Palette.ink,
  );
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      bodyLarge: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.white,
      foregroundColor: Palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      shape: const Border(bottom: BorderSide(color: Palette.line, width: 2)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.snow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.blue, width: 2),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
