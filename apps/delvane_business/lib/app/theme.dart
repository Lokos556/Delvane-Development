import 'package:material_ui/material_ui.dart';

abstract final class DelvaneColors {
  static const ink = Color(0xFF171A17);
  static const muted = Color(0xFF737A73);
  static const canvas = Color(0xFFF5F6F3);
  static const line = Color(0xFFE5E8E1);
  static const yellow = Color(0xFFFFD928);
  static const yellowSoft = Color(0xFFFFF7CB);
  static const green = Color(0xFF37624B);
  static const greenSoft = Color(0xFFEBF3EC);
}

ThemeData delvaneTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DelvaneColors.yellow,
    primary: DelvaneColors.ink,
    onPrimary: Colors.white,
    secondary: DelvaneColors.yellow,
    surface: Colors.white,
    onSurface: DelvaneColors.ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: DelvaneColors.canvas,
    fontFamily: 'Segoe UI',
    dividerColor: DelvaneColors.line,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -.7,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -.4,
      ),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5),
      bodyMedium: TextStyle(fontSize: 13, height: 1.5),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ).apply(bodyColor: DelvaneColors.ink, displayColor: DelvaneColors.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DelvaneColors.canvas,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: DelvaneColors.muted, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DelvaneColors.yellow,
        foregroundColor: DelvaneColors.ink,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DelvaneColors.ink,
        side: const BorderSide(color: DelvaneColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: DelvaneColors.canvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
  );
}
