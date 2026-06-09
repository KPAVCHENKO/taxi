import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Цвета как на сайте — две темы (тёплый кремовый и тёмная), акцент амбер.
class C {
  // light
  static const lBg = Color(0xFFFBFAF7);
  static const lBgTint = Color(0xFFF4F1E9);
  static const lSurface = Color(0xFFFFFFFF);
  static const lSurface2 = Color(0xFFF6F3EC);
  static const lSurface3 = Color(0xFFEFEBE1);
  static const lText = Color(0xFF16140F);
  static const lText2 = Color(0xFF4A463C);
  static const lText3 = Color(0xFF827C6E);
  static const lAccent = Color(0xFFE8A317);
  static const lAccent2 = Color(0xFFFFC53D);
  // dark
  static const dBg = Color(0xFF0C0B08);
  static const dBgTint = Color(0xFF13110C);
  static const dSurface = Color(0xFF16130D);
  static const dSurface2 = Color(0xFF1C1812);
  static const dSurface3 = Color(0xFF241F17);
  static const dText = Color(0xFFF6F1E6);
  static const dText2 = Color(0xFFC8C0AF);
  static const dText3 = Color(0xFF8E8675);
  static const dAccent = Color(0xFFFFC53D);
  static const dAccent2 = Color(0xFFFFD86B);

  static const accentInk = Color(0xFF1A1710);
  static const good = Color(0xFF2E9E5B);
  static const danger = Color(0xFFD23B3B);
}

/// Доступ к цветам текущей темы через Theme.of(context).extension.
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg, bgTint, surface, surface2, surface3;
  final Color text, text2, text3, accent, accent2;
  const AppPalette({
    required this.bg, required this.bgTint, required this.surface,
    required this.surface2, required this.surface3, required this.text,
    required this.text2, required this.text3, required this.accent, required this.accent2,
  });

  static const light = AppPalette(
    bg: C.lBg, bgTint: C.lBgTint, surface: C.lSurface, surface2: C.lSurface2,
    surface3: C.lSurface3, text: C.lText, text2: C.lText2, text3: C.lText3,
    accent: C.lAccent, accent2: C.lAccent2,
  );
  static const dark = AppPalette(
    bg: C.dBg, bgTint: C.dBgTint, surface: C.dSurface, surface2: C.dSurface2,
    surface3: C.dSurface3, text: C.dText, text2: C.dText2, text3: C.dText3,
    accent: C.dAccent, accent2: C.dAccent2,
  );

  @override
  AppPalette copyWith() => this;
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => this;
}

AppPalette palette(BuildContext c) =>
    Theme.of(c).extension<AppPalette>() ?? AppPalette.light;

class AppTheme {
  AppTheme._();

  static ThemeData _build(AppPalette p, Brightness b) {
    final base = ThemeData(brightness: b, useMaterial3: true);
    final tt = GoogleFonts.manropeTextTheme(base.textTheme)
        .apply(bodyColor: p.text, displayColor: p.text);
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      extensions: [p],
      colorScheme: base.colorScheme.copyWith(
        brightness: b,
        primary: p.accent,
        surface: p.surface,
        error: C.danger,
      ),
      textTheme: tt,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.unbounded(
          color: p.text, fontSize: 19, fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: p.text3),
      ),
    );
  }

  static ThemeData get light => _build(AppPalette.light, Brightness.light);
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);
}

/// Заголовок шрифтом Unbounded (как на сайте).
TextStyle heading({double size = 22, Color? color, FontWeight w = FontWeight.w700}) =>
    GoogleFonts.unbounded(fontSize: size, fontWeight: w, color: color, height: 1.1);

