import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidad visual de PetMatcher. Paleta cálida (coral) + acento teal,
/// tipografía redondeada (Nunito). Modo claro y oscuro.
class PetColors {
  static const coral = Color(0xFFFF6B6B);
  static const coralDark = Color(0xFFE85A5A);
  static const teal = Color(0xFF17C3B2);
  static const amber = Color(0xFFFFB627);
  static const violet = Color(0xFF7B61FF);

  static const cream = Color(0xFFFFF7F0);
  static const ink = Color(0xFF2B2733);
  static const inkSoft = Color(0xFF6E6A78);

  static const darkBg = Color(0xFF17151E);
  static const darkSurface = Color(0xFF221F2B);

  // Colores por categoría de efectividad.
  static const alta = Color(0xFF17C3B2);
  static const media = Color(0xFFFFB627);
  static const baja = Color(0xFFFF8C42);
  static const noRecomendado = Color(0xFFFF6B6B);

  static Color categoria(String c) => switch (c) {
        'alta' => alta,
        'media' => media,
        'baja' => baja,
        _ => noRecomendado,
      };
}

class PetGradients {
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PetColors.coral, PetColors.violet],
  );

  static const teal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PetColors.teal, Color(0xFF0E9AAE)],
  );
}

class AppTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: PetColors.coral,
      brightness: brightness,
      primary: PetColors.coral,
      secondary: PetColors.teal,
    );
    final bg = isDark ? PetColors.darkBg : PetColors.cream;
    final surface = isDark ? PetColors.darkSurface : Colors.white;

    final textTheme = GoogleFonts.nunitoTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).apply(
      bodyColor: isDark ? Colors.white : PetColors.ink,
      displayColor: isDark ? Colors.white : PetColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(surface: surface),
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : PetColors.ink,
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : PetColors.ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white10 : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFEADFD6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFEADFD6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: PetColors.coral, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PetColors.coral,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }
}
