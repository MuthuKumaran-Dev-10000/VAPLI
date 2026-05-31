import 'package:flutter/material.dart';

class AppTheme {
  // SAME VARIABLE NAMES
  // Only colors changed

  // Brand
  static const Color primary = Color(0xFFCB8C3E);

  static const Color primaryDark = Color(0xFF8A5A1E);

  static const Color accent = Color(0xFF1ABCBD);

  // Backgrounds
  static const Color background = Color(0xFF0C0D0F);

  static const Color surface = Color(0xFF141618);

  static const Color card = Color(0xFF1A1C20);

  // Borders
  static const Color border = Color(0xFF252830);

  static const Color borderHover = Color(0xFF32363F);

  // Text
  static const Color textPrimary = Color(0xFFF0EEE9);

  static const Color textSecondary = Color(0xFF8A8F9C);

  // States
  static const Color success = Color(0xFF22C55E);

  static const Color warning = Color(0xFFF59E0B);

  static const Color danger = Color(0xFFEF4444);

  static const Color disabled = Color(0xFF484C57);

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,

        brightness: Brightness.dark,

        // MAIN BG
        scaffoldBackgroundColor: background,

        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: accent,
          surface: surface,
          onPrimary: Colors.white,
          onSurface: textPrimary,
          error: danger,
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
        ),

        cardTheme: CardThemeData(
          color: card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              12,
            ),
            side: const BorderSide(
              color: border,
              width: 1,
            ),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              10,
            ),
            borderSide: const BorderSide(
              color: border,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              10,
            ),
            borderSide: const BorderSide(
              color: border,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              10,
            ),
            borderSide: const BorderSide(
              color: accent,
              width: 2,
            ),
          ),
          labelStyle: const TextStyle(
            color: textSecondary,
          ),
          hintStyle: const TextStyle(
            color: textSecondary,
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                10,
              ),
            ),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: const BorderSide(
              color: borderHover,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                10,
              ),
            ),
          ),
        ),

        dividerColor: border,

        tabBarTheme: const TabBarThemeData(
          labelColor: primary,
          unselectedLabelColor: textSecondary,
          indicatorColor: primary,
        ),

        chipTheme: ChipThemeData(
          backgroundColor: surface,
          selectedColor: accent.withOpacity(
            0.15,
          ),
          labelStyle: const TextStyle(
            color: textPrimary,
            fontSize: 12,
          ),
          side: const BorderSide(
            color: border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              8,
            ),
          ),
        ),

        dropdownMenuTheme: DropdownMenuThemeData(
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                10,
              ),
            ),
          ),
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: card,
          contentTextStyle: const TextStyle(
            color: textPrimary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              10,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
}
