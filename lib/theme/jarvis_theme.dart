import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class JarvisColors {
  // Core palette
  static const Color bg = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF12121A);
  static const Color surfaceElevated = Color(0xFF1A1A26);
  static const Color surfaceHighlight = Color(0xFF22223A);
  static const Color border = Color(0xFF252540);

  // Accent
  static const Color accentPrimary = Color(0xFF7C5CFC);
  static const Color accentSecondary = Color(0xFF00D4FF);
  static const Color accentGlow = Color(0xFF9B7CFF);

  // Text
  static const Color textPrimary = Color(0xFFEEEEFF);
  static const Color textSecondary = Color(0xFF9090B0);
  static const Color textMuted = Color(0xFF505070);

  // Provider colors
  static const Color geminiColor = Color(0xFF4285F4);
  static const Color ollamaColor = Color(0xFF38A169);
  static const Color nvidiaColor = Color(0xFF76B900);
  static const Color deepseekColor = Color(0xFF6366F1);
  static const Color localColor = Color(0xFFED8936);

  // Status
  static const Color success = Color(0xFF48BB78);
  static const Color warning = Color(0xFFF6AD55);
  static const Color error = Color(0xFFFC8181);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accentPrimary, accentSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFF0A0A0F), Color(0xFF0E0E18)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class JarvisTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: JarvisColors.bg,
      colorScheme: ColorScheme.dark(
        primary: JarvisColors.accentPrimary,
        secondary: JarvisColors.accentSecondary,
        surface: JarvisColors.surface,
        error: JarvisColors.error,
      ),
      textTheme: GoogleFonts.outfitTextTheme(const TextTheme(
        displayLarge: TextStyle(
          color: JarvisColors.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          color: JarvisColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: JarvisColors.textPrimary,
          fontSize: 16,
          height: 1.6,
        ),
        bodyMedium: TextStyle(
          color: JarvisColors.textSecondary,
          fontSize: 14,
          height: 1.5,
        ),
        labelSmall: TextStyle(
          color: JarvisColors.textMuted,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JarvisColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: JarvisColors.accentPrimary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: JarvisColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      dividerColor: JarvisColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Outfit',
          color: JarvisColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: JarvisColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: JarvisColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: JarvisColors.border, width: 0.5),
        ),
      ),
      iconTheme: const IconThemeData(color: JarvisColors.textSecondary),
    );
  }
}
