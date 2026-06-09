import 'package:flutter/material.dart';

/// Тёмная тема приложения водителя. Крупные шрифты и кнопки — под немолодых
/// и не-технических водителей.
class AppColors {
  AppColors._();

  static const bg = Color(0xFF0F1117);
  static const surface = Color(0xFF1A1D2E);
  static const surface2 = Color(0xFF232740);
  static const border = Color(0x14FFFFFF);

  static const text = Color(0xFFE2E8F0);
  static const textDim = Color(0xFF94A3B8);
  static const textFaint = Color(0xFF64748B);

  static const accent = Color(0xFFF5B800); // жёлтый бренд
  static const green = Color(0xFF34D399); // онлайн / успех
  static const greenDeep = Color(0xFF10B981);
  static const red = Color(0xFFF87171); // офлайн / опасность
  static const blue = Color(0xFF7DD3FC);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        secondary: AppColors.green,
        surface: AppColors.surface,
        error: AppColors.red,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
        fontSizeFactor: 1.05, // чуть крупнее по умолчанию
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF0F1117),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: AppColors.textFaint),
      ),
    );
  }
}
