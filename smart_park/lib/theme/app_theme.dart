import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One set of SmartPark colours; [AppTheme] serves the active one.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.textDark,
    required this.textSecondary,
    required this.textMuted,
    required this.textHint,
    required this.onInk,
    required this.accentLight,
    required this.accentWarm,
    required this.accentSoft,
    required this.accentText,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.dangerBorder,
    required this.info,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color borderStrong;
  final Color textDark;
  final Color textSecondary;
  final Color textMuted;
  final Color textHint;
  final Color onInk;
  final Color accentLight;
  final Color accentWarm;
  final Color accentSoft;
  final Color accentText;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color dangerBorder;
  final Color info;

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F4F6),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6F7FA),
    border: Color(0xFFE3E5EA),
    borderStrong: Color(0xFFC9CCD4),
    textDark: Color(0xFF1F2128),
    textSecondary: Color(0xFF4B5263),
    textMuted: Color(0xFF646A78),
    textHint: Color(0xFF8E939E),
    onInk: Color(0xFFFFFFFF),
    accentLight: Color(0xFFFFEAA8),
    accentWarm: Color(0xFFF7C846),
    accentSoft: Color(0xFFFFF4CF),
    accentText: Color(0xFF8A6A0C),
    success: Color(0xFF1F7A4A),
    successSoft: Color(0xFFE8F6EF),
    warning: Color(0xFFB45309),
    warningSoft: Color(0xFFFFF3D9),
    danger: Color(0xFFB3261E),
    dangerSoft: Color(0xFFFDECEC),
    dangerBorder: Color(0xFFF0C9C9),
    info: Color(0xFF2563EB),
  );

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF121317),
    surface: Color(0xFF1B1D22),
    surfaceAlt: Color(0xFF23262D),
    border: Color(0xFF30333B),
    borderStrong: Color(0xFF474B55),
    textDark: Color(0xFFECEDF0),
    textSecondary: Color(0xFFC4C7CF),
    textMuted: Color(0xFF9DA2AD),
    textHint: Color(0xFF767B86),
    onInk: Color(0xFF1B1D22),
    accentLight: Color(0xFF3A3220),
    accentWarm: Color(0xFF4A3B12),
    accentSoft: Color(0xFF342C16),
    accentText: Color(0xFFF2C94C),
    success: Color(0xFF6FCF97),
    successSoft: Color(0xFF16291F),
    warning: Color(0xFFF0A04B),
    warningSoft: Color(0xFF33240F),
    danger: Color(0xFFF2877F),
    dangerSoft: Color(0xFF351A1A),
    dangerBorder: Color(0xFF5C2B2B),
    info: Color(0xFF7AA7FF),
  );
}

/// SmartPark's colours. Screens use these instead of raw hex values so the
/// app stays consistent and can switch between light and dark. Text
/// colours meet WCAG AA contrast (4.5:1) on [surface] and [background].
///
/// The colours are getters over the active [AppPalette], so they can't be
/// used in `const` expressions.
class AppTheme {
  static AppPalette _palette = AppPalette.light;

  static AppPalette get palette => _palette;
  static bool get isDark => _palette.brightness == Brightness.dark;

  /// Switches palettes. The caller must rebuild the widget tree afterwards
  /// (see ThemeController).
  static void usePalette(AppPalette palette) => _palette = palette;

  // Surfaces
  static Color get background => _palette.background;
  static Color get surface => _palette.surface;

  /// Input fills, nested panels and other areas set off from a card.
  static Color get surfaceAlt => _palette.surfaceAlt;
  static Color get border => _palette.border;
  static Color get borderStrong => _palette.borderStrong;

  // Text
  static Color get textDark => _palette.textDark;
  static Color get textSecondary => _palette.textSecondary;
  static Color get textMuted => _palette.textMuted;

  /// Placeholder text only; too light for anything the user must read.
  static Color get textHint => _palette.textHint;

  /// Strong filled elements (primary dark buttons, selected chips). Same
  /// as [textDark], so it inverts in dark mode; pair it with [onInk].
  static Color get ink => _palette.textDark;
  static Color get onInk => _palette.onInk;

  // Brand
  static const Color accent = Color(0xFFF2C335);

  /// Text and icons on [accent]; dark in both modes.
  static const Color onAccent = Color(0xFF1F2128);
  static Color get accentLight => _palette.accentLight;
  static Color get accentWarm => _palette.accentWarm;
  static Color get accentSoft => _palette.accentSoft;

  /// Readable text/icons on [accentSoft] and the yellow gradients.
  static Color get accentText => _palette.accentText;

  // Status
  static Color get success => _palette.success;
  static Color get successSoft => _palette.successSoft;
  static Color get warning => _palette.warning;
  static Color get warningSoft => _palette.warningSoft;
  static Color get danger => _palette.danger;
  static Color get dangerSoft => _palette.dangerSoft;
  static Color get dangerBorder => _palette.dangerBorder;
  static Color get info => _palette.info;

  // Corner radii: chips/icon boxes, controls, cards, hero panels.
  static const double radiusSmall = 8;
  static const double radius = 12;
  static const double radiusLarge = 16;
  static const double radiusXLarge = 20;

  /// The Material theme for the active palette.
  static ThemeData get theme {
    final bool dark = isDark;
    final TextTheme baseText = dark
        ? ThemeData(brightness: Brightness.dark).textTheme
        : ThemeData(brightness: Brightness.light).textTheme;
    return ThemeData(
      useMaterial3: true,
      brightness: _palette.brightness,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      dividerColor: border,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: _palette.brightness,
        error: danger,
        surface: surface,
        onSurface: textDark,
        outline: borderStrong,
        outlineVariant: border,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(
        baseText,
      ).apply(bodyColor: textDark, displayColor: textDark),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textDark,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(color: surface, surfaceTintColor: surface),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: surface,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: surface,
      ),
      popupMenuTheme: PopupMenuThemeData(color: surface),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: onInk,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: textDark),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 8,
        indicatorColor: accent.withValues(alpha: 0.3),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textDark,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: textDark);
          }
          return IconThemeData(color: textMuted);
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: textDark,
        unselectedItemColor: textMuted,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
