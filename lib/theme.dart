import 'package:flutter/material.dart';

/// Brand colours used across the app (cards, charts, status).
class AppColors {
  static const brand = Color(0xFF0F766E); // deep teal
  static const good = Color(0xFF16A34A);
  static const warn = Color(0xFFD97706);
  static const bad = Color(0xFFDC2626);
  static const info = Color(0xFF2563EB);
}

/// Colours the user can pick in Settings (English name, Arabic name, colour).
const accentChoices = <(String, String, Color)>[
  ('Teal', 'فيروزي', Color(0xFF0F766E)),
  ('Blue', 'أزرق', Color(0xFF1D4ED8)),
  ('Purple', 'بنفسجي', Color(0xFF6D28D9)),
  ('Green', 'أخضر', Color(0xFF15803D)),
  ('Red', 'أحمر', Color(0xFFBE123C)),
  ('Orange', 'برتقالي', Color(0xFFC2410C)),
  ('Brown', 'بني', Color(0xFF7C4A2D)),
  ('Grey', 'رمادي', Color(0xFF334155)),
];

/// The colour chosen on this device; set by the app before each build.
Color appAccent = AppColors.brand;

/// Background of the big coloured cards (home and month), from the chosen colour.
List<Color> heroGradient() => [
      appAccent,
      Color.lerp(appAccent, Colors.black, .18)!,
      Color.lerp(appAccent, Colors.black, .32)!,
    ];

ThemeData buildTheme([Brightness brightness = Brightness.light, Color? seed]) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed ?? AppColors.brand,
    brightness: brightness,
    surface: dark ? const Color(0xFF0E1416) : const Color(0xFFF3F6F6),
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'NotoSans',
    fontFamilyFallback: const ['NotoSansArabic'],
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
  );
  final radius = BorderRadius.circular(18);
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      // base.textTheme carries colors only (sizes are merged in later), so sizes are set here.
      titleTextStyle: base.textTheme.headlineSmall!.copyWith(fontSize: 24, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -.3),
    ),
    cardTheme: CardThemeData(
      elevation: dark ? 0 : 1.5,
      shadowColor: const Color(0x2A0F3D3A),
      color: dark ? const Color(0xFF162024) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: dark ? BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)) : BorderSide.none),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF172024) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.outlineVariant)),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF131A1D) : Colors.white,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium!.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? const Color(0xFF131A1D) : Colors.white,
      indicatorColor: scheme.primaryContainer,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: .5), space: 1),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    tabBarTheme: TabBarThemeData(dividerColor: Colors.transparent, labelStyle: base.textTheme.titleSmall!.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
  );
}
