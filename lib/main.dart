import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'splash_screen.dart'; // Import the new splash screen file
import 'theme_provider.dart'; // Import theme provider

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the .env file before running the app
  await dotenv.load(fileName: ".env");

  // Load saved theme preference
  final themeProvider = ThemeProvider();
  await themeProvider.loadFromPrefs();

  runApp(BUddyApp(themeProvider: themeProvider));
}

// The root widget of the application.
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
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'BUddy',
            theme: ThemeData(
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
                seedColor: colors.accent,
                brightness: colors.brightness,
              ),
            ),
            home: const SplashScreen(), // Start with the splash screen.
          );
        },
      ),
    );
  }
}
