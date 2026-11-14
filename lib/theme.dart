import 'package:flutter/material.dart';

import 'l10n.dart';

/// Brand colours used across the app (cards, charts, status), from the hospital design guide.
class AppColors {
  static const brand = Color(0xFF0F766E); // teal-700: the guide's teal-600 is too light for white text (3.7:1)
  static const save = Color(0xFF2563EB); // blue-600, save / open
  static const good = Color(0xFF059669); // emerald-600, print / success
  static const warn = Color(0xFFD97706); // amber-600, bills / warnings
  static const bad = Color(0xFFBE123C); // rose-700, delete
  static const info = Color(0xFF2563EB);
  static const dark = Color(0xFF1E293B); // slate-800, table heads
  static const page = Color(0xFFF1F5F9); // slate-100, page background
  static const ink = Color(0xFF0F172A); // slate-900, text
  static const muted = Color(0xFF64748B); // slate-500
  static const label = Color(0xFF475569); // slate-600
  static const line = Color(0xFFE2E8F0); // slate-200
  static const field = Color(0xFFCBD5E1); // slate-300

  /// The header: slate-900 → teal-900 → cyan-900, from the reading side.
  static const header = [Color(0xFF0F172A), Color(0xFF134E4A), Color(0xFF164E63)];
}

/// Status colours that stay readable as text in both light and dark mode
/// (the fixed [AppColors] are too pale on white for small text, and too dark on the night theme).
extension StatusColors on ColorScheme {
  bool get _dark => brightness == Brightness.dark;
  Color get good => _dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
  Color get warning => _dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  Color get bad => _dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
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

/// Background of the big coloured card on the Month page: one flat dark colour (no gradient),
/// the header's teal, or a darker shade of the chosen colour.
Color heroColor() => appAccent == accentChoices.first.$3 ? AppColors.header[1] : Color.lerp(appAccent, Colors.black, .25)!;

/// Lets page headers open the side panel: provided by the main screen around the open section.
class MenuScope extends InheritedWidget {
  const MenuScope({super.key, required this.onMenu, required super.child});
  final VoidCallback onMenu;

  static MenuScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MenuScope>();

  @override
  bool updateShouldNotify(MenuScope old) => old.onMenu != onMenu;
}

/// The button that opens the side panel, or null where there is none (pages opened on top, which go back instead).
Widget? menuButton(BuildContext context) {
  final menu = MenuScope.maybeOf(context);
  if (menu == null || (ModalRoute.of(context)?.canPop ?? false)) return null;
  return IconButton(tooltip: tx('Menu', 'القائمة'), onPressed: menu.onMenu, icon: const Icon(Icons.menu));
}

/// The dark gradient header of every page, with white title and icons.
/// On a section's own page (nothing to go back to) it starts with the menu button that opens the side panel.
class HeaderBar extends StatelessWidget implements PreferredSizeWidget {
  const HeaderBar({super.key, this.leading, this.automaticallyImplyLeading = true, this.title, this.actions, this.bottom, this.centerTitle});
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool? centerTitle;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final lead = leading ?? (automaticallyImplyLeading ? menuButton(context) : null);
    return AppBar(
      leading: lead,
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: title,
      actions: actions == null ? null : [for (final a in actions!) OnHeader(child: a)],
      bottom: bottom,
      centerTitle: centerTitle,
      flexibleSpace: const _HeaderGradient(),
      backgroundColor: AppColors.header[1],
      foregroundColor: Colors.white,
    );
  }
}

class _HeaderGradient extends StatelessWidget {
  const _HeaderGradient();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          // "to left" in the design: dark slate at the reading start.
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart.resolve(Directionality.of(context)),
            end: AlignmentDirectional.centerEnd.resolve(Directionality.of(context)),
            colors: AppColors.header,
          ),
          boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 15, offset: Offset(0, 10), spreadRadius: -3)],
        ),
      );
}

/// Buttons placed on the dark header: white text and icons, glass-style filled buttons.
class OnHeader extends StatelessWidget {
  const OnHeader({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final glass = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0x26FFFFFF)));
    return Theme(
      data: t.copyWith(
        iconTheme: const IconThemeData(color: Colors.white),
        iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Colors.white)),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: const Color(0x1AFFFFFF), shape: glass, textStyle: const TextStyle(fontWeight: FontWeight.w700))),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
        popupMenuTheme: t.popupMenuTheme,
      ),
      child: IconTheme(data: const IconThemeData(color: Colors.white), child: child),
    );
  }
}

ThemeData buildTheme([Brightness brightness = Brightness.light, Color? seed]) {
  final dark = brightness == Brightness.dark;
  final primary = seed ?? AppColors.brand;
  final page = dark ? const Color(0xFF0B1220) : AppColors.page;
  final card = dark ? const Color(0xFF111A2B) : Colors.white;
  final line = dark ? const Color(0xFF243247) : AppColors.line;
  final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
    primary: dark ? Color.lerp(primary, Colors.white, .25) : primary,
    onPrimary: Colors.white,
    surface: page,
    onSurface: dark ? const Color(0xFFE2E8F0) : AppColors.ink,
    onSurfaceVariant: dark ? const Color(0xFF94A3B8) : AppColors.muted,
    outline: dark ? const Color(0xFF475569) : AppColors.field,
    outlineVariant: line,
    surfaceContainerHighest: dark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
  );
  final themed = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Cairo',
    fontFamilyFallback: const ['NotoSansArabic', 'NotoSans'],
    scaffoldBackgroundColor: page,
    visualDensity: VisualDensity.standard,
  );
  // Same-width digits everywhere, so quantities and money line up in tables and tiles.
  const digits = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
  final t = themed.textTheme;
  final base = themed.copyWith(
    textTheme: TextTheme(
      displayLarge: t.displayLarge?.merge(digits),
      displayMedium: t.displayMedium?.merge(digits),
      displaySmall: t.displaySmall?.merge(digits),
      headlineLarge: t.headlineLarge?.merge(digits),
      headlineMedium: t.headlineMedium?.merge(digits),
      headlineSmall: t.headlineSmall?.merge(digits),
      titleLarge: t.titleLarge?.merge(digits),
      titleMedium: t.titleMedium?.merge(digits).copyWith(fontWeight: FontWeight.w700),
      titleSmall: t.titleSmall?.merge(digits).copyWith(fontWeight: FontWeight.w700),
      bodyLarge: t.bodyLarge?.merge(digits).copyWith(fontWeight: FontWeight.w600),
      bodyMedium: t.bodyMedium?.merge(digits).copyWith(fontWeight: FontWeight.w600),
      bodySmall: t.bodySmall?.merge(digits),
      labelLarge: t.labelLarge?.merge(digits).copyWith(fontWeight: FontWeight.w700),
      labelMedium: t.labelMedium?.merge(digits).copyWith(fontWeight: FontWeight.w700),
      labelSmall: t.labelSmall?.merge(digits),
    ),
  );
  final r12 = BorderRadius.circular(12), r16 = BorderRadius.circular(16);
  ButtonStyle solid(Color bg) => FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: r12),
        textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 14),
        elevation: 0,
      );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.header[1],
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: .5),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r16, side: BorderSide(color: line.withValues(alpha: .8))),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF0F172A) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: dark ? const Color(0xFF94A3B8) : AppColors.label),
      border: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide(color: scheme.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: r12, borderSide: const BorderSide(color: Color(0xFF14B8A6), width: 2)),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(style: solid(scheme.primary)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: solid(AppColors.save)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: dark ? const Color(0xFF1E293B) : AppColors.page,
            foregroundColor: dark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: r12),
            textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 14))),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: r12), textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        extendedTextStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: r16)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: dark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium!.copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      indicatorColor: dark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
      selectedLabelTextStyle: TextStyle(fontWeight: FontWeight.w800, color: dark ? const Color(0xFF5EEAD4) : const Color(0xFF134E4A)),
      unselectedLabelTextStyle: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r16),
      titleTextStyle: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.dark,
      contentTextStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: r12, side: const BorderSide(color: Color(0xFF475569))),
    ),
    dividerTheme: DividerThemeData(color: line, space: 1),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
      // Filter pills: the chosen one is filled with the main colour, the rest match the page.
      labelStyle: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          color: WidgetStateColor.resolveWith((st) => st.contains(WidgetState.selected) ? (dark ? AppColors.ink : Colors.white) : scheme.onSurface)),
      color: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? (dark ? const Color(0xFF5EEAD4) : scheme.primary) : page),
      checkmarkColor: dark ? AppColors.ink : Colors.white,
      side: WidgetStateBorderSide.resolveWith((st) => BorderSide(color: st.contains(WidgetState.selected) ? (dark ? const Color(0xFF5EEAD4) : scheme.primary) : line)),
    ),
    tabBarTheme: TabBarThemeData(dividerColor: Colors.transparent, labelStyle: base.textTheme.titleSmall!.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
  );
}
