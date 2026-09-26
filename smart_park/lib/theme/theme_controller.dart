import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

enum AppThemeMode { system, light, dark }

/// Holds the user's light/dark choice, saves it on the device, and swaps
/// [AppTheme]'s palette. SmartParkApp listens and rebuilds the whole tree.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const String _prefsKey = 'theme_mode';

  AppThemeMode _mode = AppThemeMode.light;
  AppThemeMode get mode => _mode;

  /// Reads the saved choice. Call once before runApp.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_prefsKey);
      _mode = AppThemeMode.values.firstWhere(
        (AppThemeMode m) => m.name == saved,
        orElse: () => AppThemeMode.light,
      );
    } on Exception {
      _mode = AppThemeMode.light;
    }
    WidgetsBinding.instance.addObserver(this);
    _apply(notify: false);
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _apply();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } on Exception {
      // Not saved; the choice still applies until the app restarts.
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == AppThemeMode.system) _apply();
  }

  void _apply({bool notify = true}) {
    final bool dark = switch (_mode) {
      AppThemeMode.dark => true,
      AppThemeMode.light => false,
      AppThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    final AppPalette palette = dark ? AppPalette.dark : AppPalette.light;
    if (palette == AppTheme.palette) return;
    AppTheme.usePalette(palette);
    if (notify) notifyListeners();
  }
}
