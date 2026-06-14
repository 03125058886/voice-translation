import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg950 = Color(0xFF070B12);
  static const bg900 = Color(0xFF0D1117);
  static const bg800 = Color(0xFF161B22);
  static const bg700 = Color(0xFF21262D);
  static const bg600 = Color(0xFF30363D);
  static const bg500 = Color(0xFF484F58);

  static const brand600 = Color(0xFF4C6EF5);
  static const brand500 = Color(0xFF5C7CFA);
  static const brand400 = Color(0xFF748FFC);
  static const brand300 = Color(0xFF91A7FF);

  static const green400 = Color(0xFF4ADE80);
  static const green500 = Color(0xFF22C55E);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const yellow400 = Color(0xFFFACC15);
  static const purple400 = Color(0xFFC084FC);
  static const cyan400 = Color(0xFF22D3EE);

  static const white = Colors.white;
  static const surface400 = Color(0xFF8B949E);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg950,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.brand600,
          secondary: AppColors.brand400,
          surface: AppColors.bg800,
          onSurface: AppColors.white,
          error: AppColors.red500,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bg800,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.bg600),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.bg600),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.brand600, width: 2),
          ),
          hintStyle: const TextStyle(color: AppColors.bg500, fontSize: 14),
          labelStyle: const TextStyle(color: AppColors.surface400, fontSize: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand600,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
            elevation: 0,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg900,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: AppColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: AppColors.white),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.bg700),
        cardTheme: CardThemeData(
          color: AppColors.bg800,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.bg700),
          ),
        ),
      );
}
