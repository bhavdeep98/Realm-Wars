import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// Veilborn Design System — Gothic Luxury
// Obsidian foundations. Cold silver. Bone white. Blood crimson accents.
// =============================================================================

class VeilbornColors {
  // Backgrounds — layered darkness
  static const obsidian = Color(0xFF080810);      // deepest bg
  static const abyss = Color(0xFF0D0D1A);          // card bg
  static const voidDark = Color(0xFF12121F);        // surface
  static const rifted = Color(0xFF1A1A2E);          // elevated surface
  static const hollow = Color(0xFF22223A);          // borders/dividers

  // Text
  static const boneWhite = Color(0xFFF0EDE8);       // primary text
  static const ashGrey = Color(0xFF9B9BAF);          // secondary text
  static const ghostSilver = Color(0xFFD4D4E8);     // subtle text

  // Accents
  static const veilCrimson = Color(0xFFB01020);     // danger / destruction
  static const bloodRed = Color(0xFF8B0000);        // deep accent
  static const spectreViolet = Color(0xFF6B4FA0);   // Specter type
  static const revenantSilver = Color(0xFF8A9BB8);  // Revenant type
  static const phantomIndigo = Color(0xFF3D4FAA);   // Phantom type
  static const behemothCrimson = Color(0xFF8B2020); // Behemoth type
  static const veilGold = Color(0xFFB8922A);        // legendary / premium
  static const veilGoldLight = Color(0xFFD4A84B);   // gold highlight

  // Rarity colors
  static const common = Color(0xFF7A7A8A);
  static const rare = Color(0xFF4A7AB5);
  static const epic = Color(0xFF7B4FB8);
  static const legendary = Color(0xFFB8922A);

  // Gradients
  static const riftGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A0A2E), Color(0xFF080810)],
  );

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1A2E), Color(0xFF0D0D1A)],
  );

  static const legendaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A1A00), Color(0xFF1A0D00), Color(0xFF2A1800)],
  );

  static const veilPulse = RadialGradient(
    center: Alignment.center,
    radius: 1.2,
    colors: [Color(0xFF1A1A3A), Color(0xFF080810)],
  );

  static Color rarityColor(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'legendary': return legendary;
      case 'epic': return epic;
      case 'rare': return rare;
      default: return common;
    }
  }

  static Color typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'specter': return spectreViolet;
      case 'revenant': return revenantSilver;
      case 'phantom': return phantomIndigo;
      case 'behemoth': return behemothCrimson;
      default: return ashGrey;
    }
  }
}

class VeilbornTextStyles {
  // Display — Cinzel for titles, headings, card names
  static TextStyle display(double size, {Color? color, FontWeight? weight}) =>
    TextStyle(
      fontFamily: 'Cinzel',
      fontSize: size,
      fontWeight: weight ?? FontWeight.w700,
      color: color ?? VeilbornColors.boneWhite,
      letterSpacing: size > 24 ? 2.0 : 1.2,
      height: 1.1,
    );

  // Body — Crimson Text for lore, narration, descriptions
  static TextStyle body(double size, {Color? color, bool italic = false}) =>
    TextStyle(
      fontFamily: 'Crimson',
      fontSize: size,
      color: color ?? VeilbornColors.boneWhite,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      height: 1.6,
    );

  // UI — system font for stats, numbers, labels
  static TextStyle ui(double size, {Color? color, FontWeight? weight}) =>
    TextStyle(
      fontFamily: 'Cinzel',
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? VeilbornColors.ashGrey,
      letterSpacing: 0.8,
    );

  // Stat number — bold, prominent
  static TextStyle stat(double size, {Color? color}) =>
    TextStyle(
      fontFamily: 'Cinzel',
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: color ?? VeilbornColors.boneWhite,
      letterSpacing: -0.5,
    );
}

class VeilbornTheme {
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: VeilbornColors.obsidian,
    colorScheme: const ColorScheme.dark(
      primary: VeilbornColors.veilCrimson,
      secondary: VeilbornColors.spectreViolet,
      surface: VeilbornColors.voidDark,
      error: VeilbornColors.veilCrimson,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Cinzel',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: VeilbornColors.boneWhite,
        letterSpacing: 2,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: VeilbornColors.abyss,
      selectedItemColor: VeilbornColors.boneWhite,
      unselectedItemColor: VeilbornColors.ashGrey,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: VeilbornColors.abyss,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: VeilbornColors.hollow, width: 1),
      ),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VeilbornColors.veilCrimson,
        foregroundColor: VeilbornColors.boneWhite,
        textStyle: const TextStyle(
          fontFamily: 'Cinzel',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VeilbornColors.rifted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: VeilbornColors.hollow),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: VeilbornColors.hollow),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: VeilbornColors.veilCrimson),
      ),
      hintStyle: const TextStyle(color: VeilbornColors.ashGrey, fontFamily: 'Crimson'),
      labelStyle: const TextStyle(color: VeilbornColors.ashGrey, fontFamily: 'Cinzel'),
    ),
  );
}

// Spacing system
class VeilbornSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}
