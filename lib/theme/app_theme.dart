import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Deep dark backgrounds
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF12121A);
  static const Color surfaceVariant = Color(0xFF1A1A26);
  static const Color card = Color(0xFF1E1E2E);

  // Purple/violet accent palette
  static const Color primary = Color(0xFF8B5CF6);
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color primaryDark = Color(0xFF7C3AED);
  static const Color secondary = Color(0xFF06B6D4);
  static const Color accent = Color(0xFFEC4899);

  // Text colors
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);

  // Glassmorphism
  static const Color glass = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);

  // Player gradient
  static const List<Color> playerGradient = [
    Color(0xFF1a0533),
    Color(0xFF0a0a1a),
  ];
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary),
        headlineMedium: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
        headlineSmall: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
        bodyLarge:
            GoogleFonts.inter(fontSize: 16, color: AppColors.textPrimary),
        bodyMedium:
            GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
        bodySmall:
            GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
        labelLarge: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withOpacity(0.2),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary);
          }
          return const IconThemeData(color: AppColors.textMuted);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceVariant,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withOpacity(0.1),
        trackHeight: 3.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      dividerTheme:
          const DividerThemeData(color: AppColors.surfaceVariant, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
    );
  }
}
