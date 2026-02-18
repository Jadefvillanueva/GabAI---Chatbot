import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds all the custom colors used across the app for a given theme mode.
class AppThemeColors {
  final Color background;
  final Color primaryText;
  final Color secondaryText;
  final Color userBubble;
  final Color userBubbleText;
  final Color aiBubble;
  final Color aiBorder;
  final Color accent;
  final Color accentSecondary;
  final Color gradientStart;
  final Color gradientMid;
  final Color gradientEnd;
  final Color inputBarBackground;
  final Color inputBarBorder;
  final Color headerGlass;
  final Color headerBorder;
  final Color chipBackground;
  final Color chipBorder;
  final Color chipText;
  final Color surfaceOverlay;
  final Brightness brightness;

  const AppThemeColors({
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.userBubble,
    required this.userBubbleText,
    required this.aiBubble,
    required this.aiBorder,
    required this.accent,
    required this.accentSecondary,
    required this.gradientStart,
    required this.gradientMid,
    required this.gradientEnd,
    required this.inputBarBackground,
    required this.inputBarBorder,
    required this.headerGlass,
    required this.headerBorder,
    required this.chipBackground,
    required this.chipBorder,
    required this.chipText,
    required this.surfaceOverlay,
    required this.brightness,
  });

  /// The shared gradient used for primary actions.
  List<Color> get actionGradient => [gradientStart, gradientMid, gradientEnd];

  /// Light mode — vibrant orange-to-blue gradient aesthetic.
  static const light = AppThemeColors(
    background: Color(0xFFF8F9FC),
    primaryText: Color(0xFF1A1A2E),
    secondaryText: Color(0xFF6B7280),
    userBubble: Color(0xFFFF8A50), // warm orange
    userBubbleText: Colors.white,
    aiBubble: Colors.white,
    aiBorder: Color(0xFFE5E7EB),
    accent: Color(0xFFFF8A50), // orange
    accentSecondary: Color(0xFF1E88E5), // blue
    gradientStart: Color(0xFFFF8A50),
    gradientMid: Color(0xFF64B5F6),
    gradientEnd: Color(0xFF1E88E5),
    inputBarBackground: Color(0xF2FFFFFF), // ~90% white
    inputBarBorder: Color(0x4DFFFFFF), // ~30% white
    headerGlass: Color(0x1AFFFFFF), // ~10% white
    headerBorder: Color(0x33FFFFFF), // ~20% white
    chipBackground: Color(0x26FFFFFF), // ~15% white
    chipBorder: Color(0x40FFFFFF), // ~25% white
    chipText: Color(0xFF1A1A2E),
    surfaceOverlay: Color(0x0DFFFFFF), // ~5% white
    brightness: Brightness.light,
  );

  /// Dark mode — high-contrast monochrome with subtle accents.
  static const dark = AppThemeColors(
    background: Colors.black,
    primaryText: Color(0xFFF9FAFB),
    secondaryText: Color(0xFF9CA3AF),
    userBubble: Color(0xFFF9FAFB), // white bubble
    userBubbleText: Colors.black,
    aiBubble: Color(0xFF111111),
    aiBorder: Color(0xFF2A2A2A),
    accent: Color(0xFFF9FAFB), // white accent
    accentSecondary: Color(0xFF6B7280),
    gradientStart: Color(0xFF111111),
    gradientMid: Color(0xFF0A0A0A),
    gradientEnd: Color(0xFF050505),
    inputBarBackground: Color(0xFF111111),
    inputBarBorder: Color(0xFF2A2A2A),
    headerGlass: Color(0x0DFFFFFF), // ~5% white
    headerBorder: Color(0x1AFFFFFF), // ~10% white
    chipBackground: Color(0xFF111111),
    chipBorder: Color(0xFF2A2A2A),
    chipText: Color(0xFFF9FAFB),
    surfaceOverlay: Color(0x0DFFFFFF),
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
