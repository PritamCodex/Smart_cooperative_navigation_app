import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Premium Vibrant Palette
  static const Color primaryColor = Color(0xFF2D6CDF); // Electric Blue
  static const Color accentColor = Color(0xFF00FF9D);  // Neon Green
  static const Color warningColor = Color(0xFFFFB800); // Bright Amber
  static const Color errorColor = Color(0xFFFF2E63);   // Hot Pink/Red
  static const Color surfaceColor = Color(0x1AFFFFFF); // Glassy White (10%)
  static const Color backgroundColor = Color(0xFF0F111A); // Deep Navy/Black
  
  // Legacy/Specific Alert Colors (Mapped to Vibrant Palette)
  static const Color safeGreen = accentColor;
  static const Color alertYellow = Color(0xFFFFD600); // Bright Yellow
  static const Color alertOrange = warningColor;
  static const Color alertRed = errorColor;
  static const Color primaryRed = primaryColor; // Map old primary to new primary
  static const Color accentTeal = accentColor; // Map old accent to new accent
  
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF); // 70% White
  
  // Text Styles
  static TextStyle get headerStyle => GoogleFonts.rajdhani(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    letterSpacing: 1.0,
  );

  static TextStyle get titleStyle => GoogleFonts.rajdhani(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get bodyStyle => GoogleFonts.robotoMono(
    fontSize: 14,
    color: textSecondary,
  );

  static TextStyle get labelStyle => GoogleFonts.robotoMono(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    letterSpacing: 0.5,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
        surface: surfaceColor,
        background: backgroundColor,
        error: errorColor,
      ),
      textTheme: GoogleFonts.outfitTextTheme( // Modern, rounded font
        ThemeData.dark().textTheme,
      ).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      cardTheme: const CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)), // Fluffy corners
          side: BorderSide(color: Colors.white24, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor, // Changed from primaryRed to primaryColor
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30), // Pill shape
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.rajdhani(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 1.5,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
    );
  }
}