import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'splash_screen.dart';
import 'theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  final themeProvider = ThemeProvider();
  await themeProvider.loadFromPrefs();

  runApp(BUddyApp(themeProvider: themeProvider));
}

class BUddyApp extends StatefulWidget {
  final ThemeProvider themeProvider;

  const BUddyApp({super.key, required this.themeProvider});

  @override
  State<BUddyApp> createState() => _BUddyAppState();
}

class _BUddyAppState extends State<BUddyApp> {
  ThemeData? _cachedTheme;
  bool? _lastIsDark;

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      themeProvider: widget.themeProvider,
      child: AnimatedBuilder(
        animation: widget.themeProvider,
        builder: (context, _) {
          final colors = widget.themeProvider.colors;
          final isDark = widget.themeProvider.isDarkMode;

          // Only update system chrome & rebuild ThemeData when theme changes
          if (_lastIsDark != isDark) {
            _lastIsDark = isDark;
            SystemChrome.setSystemUIOverlayStyle(
              isDark
                  ? SystemUiOverlayStyle.light.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: Colors.black,
                    )
                  : SystemUiOverlayStyle.dark.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: colors.background,
                    ),
            );

            _cachedTheme = ThemeData(
              brightness: colors.brightness,
              primaryColor: colors.accent,
              scaffoldBackgroundColor: colors.background,
              textTheme:
                  GoogleFonts.interTextTheme(
                    ThemeData(brightness: colors.brightness).textTheme,
                  ).apply(
                    bodyColor: colors.primaryText,
                    displayColor: colors.primaryText,
                  ),
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFFF8A50),
                brightness: colors.brightness,
              ),
              splashFactory: InkSparkle.splashFactory,
            );
          }

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'BUddy',
            theme: _cachedTheme,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
