import 'package:flutter/material.dart';

abstract final class AppColors {
  static const paper = Color(0xFFF7F6F1);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF2B2922);
  static const muted = Color(0xFF6E6A5B);
  static const line = Color(0xFFE7E4DA);
  static const lineSoft = Color(0xFFEFEDE5);
  static const green = Color(0xFF1D5C49);
  static const greenInk = Color(0xFF14493A);
  static const greenBackground = Color(0xFFE9F1ED);
  static const red = Color(0xFFB5382A);
  static const redBackground = Color(0xFFF8ECE9);
  static const amberBackground = Color(0xFFFBF3DF);
  static const amberInk = Color(0xFF8A6A1F);
  static const disabled = Color(0xFFA7A392);
}

ThemeData buildAppTheme() {
  const radius = BorderRadius.all(Radius.circular(14));
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.green,
    brightness: Brightness.light,
    primary: AppColors.green,
    onPrimary: Colors.white,
    surface: AppColors.card,
    onSurface: AppColors.ink,
    error: AppColors.red,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    fontFamilyFallback: const [
      'PingFang SC',
      'HarmonyOS Sans SC',
      'MiSans',
      'Microsoft YaHei',
    ],
    textTheme: const TextTheme(
      bodyLarge: TextStyle(
        fontSize: 18,
        color: AppColors.ink,
        height: 1.35,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      bodyMedium: TextStyle(
        fontSize: 18,
        color: AppColors.ink,
        height: 1.35,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      bodySmall: TextStyle(
        fontSize: 18,
        color: AppColors.muted,
        height: 1.35,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      titleLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      titleMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      labelLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.line),
        borderRadius: radius,
      ),
    ),
    dividerColor: AppColors.lineSoft,
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: TextStyle(
        color: AppColors.disabled,
        fontSize: 18,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.green, width: 2),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        height: 1.4,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        textStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        foregroundColor: AppColors.greenInk,
        side: const BorderSide(color: AppColors.green, width: 1.5),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.greenInk,
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      contentTextStyle: TextStyle(
        fontSize: 18,
        height: 1.5,
        color: AppColors.ink,
      ),
    ),
  );
}
