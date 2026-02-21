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

class BUddyApp extends StatelessWidget {
  final ThemeProvider themeProvider;

  const BUddyApp({super.key, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      themeProvider: themeProvider,
      child: AnimatedBuilder(
        animation: themeProvider,
        builder: (context, _) {
          final colors = themeProvider.colors;
          final isDark = themeProvider.isDarkMode;

          // Match system chrome to current theme
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

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'BUddy',
            theme: ThemeData(
              brightness: colors.brightness,
              primaryColor: colors.accent,
              scaffoldBackgroundColor: Colors.black,
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
            ),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
