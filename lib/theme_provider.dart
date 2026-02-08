import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds all the custom colors used across the app for a given theme mode.
class AppThemeColors {
  final Color background;
  final Color primaryText;
  final Color secondaryText;
  final Color userBubble;
  final Color aiBubble;
  final Color aiBorder;
  final Color accent;
  final Color gradientStart;
  final Color gradientMid;
  final Color gradientEnd;
  final Color inputBarBackground;
  final Brightness brightness;

  const AppThemeColors({
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.userBubble,
    required this.aiBubble,
    required this.aiBorder,
    required this.accent,
    required this.gradientStart,
    required this.gradientMid,
    required this.gradientEnd,
    required this.inputBarBackground,
    required this.brightness,
  });

  /// Light mode colors (original design).
  static const light = AppThemeColors(
    background: Colors.white,
    primaryText: Color(0xFF333333),
    secondaryText: Color(0xFF666666),
    userBubble: Color(0xFFF2E7FF),
    aiBubble: Colors.white,
    aiBorder: Color(0xFFE0E0E0),
    accent: Color(0xFF6A1B9A),
    gradientStart: Color(0xFFF2E7FF),
    gradientMid: Color(0xFFE7F0FF),
    gradientEnd: Color(0xFFFCE7F7),
    inputBarBackground: Colors.white,
    brightness: Brightness.light,
  );

  /// Dark mode colors.
  static const dark = AppThemeColors(
    background: Color(0xFF121212),
    primaryText: Color(0xFFE0E0E0),
    secondaryText: Color(0xFF9E9E9E),
    userBubble: Color(0xFF2D1B4E),
    aiBubble: Color(0xFF1E1E1E),
    aiBorder: Color(0xFF333333),
    accent: Color(0xFFCE93D8),
    gradientStart: Color(0xFF1A0A2E),
    gradientMid: Color(0xFF0A1628),
    gradientEnd: Color(0xFF1E0A1A),
    inputBarBackground: Color(0xFF1E1E1E),
    brightness: Brightness.dark,
  );
}

/// A simple theme notifier that persists the user's choice.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'is_dark_mode';

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  AppThemeColors get colors =>
      _isDarkMode ? AppThemeColors.dark : AppThemeColors.light;

  /// Load saved preference.
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_key) ?? false;
    notifyListeners();
  }

  /// Toggle between light and dark mode.
  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDarkMode);
  }
}

/// InheritedWidget to provide theme data down the widget tree.
class ThemeScope extends InheritedNotifier<ThemeProvider> {
  const ThemeScope({
    super.key,
    required ThemeProvider themeProvider,
    required super.child,
  }) : super(notifier: themeProvider);

  static ThemeProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope found in context');
    return scope!.notifier!;
  }
}
