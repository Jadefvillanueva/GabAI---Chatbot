import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'splash_screen.dart'; // Import the new splash screen file

// --- App Theme Colors ---
const DESIGN_BACKGROUND = Colors.white;
const DESIGN_PRIMARY_TEXT = Color(0xFF333333);
const DESIGN_SECONDARY_TEXT = Color(0xFF666666);
const DESIGN_USER_BUBBLE = Color(0xFFF2E7FF); // User's chat bubble color.
const DESIGN_AI_BUBBLE = Colors.white;
const DESIGN_AI_BORDER = Color(0xFFE0E0E0); // AI's chat bubble border color.
const DESIGN_ACCENT = Color(0xFF6A1B9A); // Main brand/accent color.

// Colors for the background gradient blob.
const GRADIENT_START = Color(0xFFF2E7FF);
const GRADIENT_MID = Color(0xFFE7F0FF);
const GRADIENT_END = Color(0xFFFCE7F7);
// --- End Colors ---

void main() async {
  // Load the .env file before running the app
  await dotenv.load(fileName: ".env");

  runApp(const BUddyApp());
}

// The root widget of the application.
class BUddyApp extends StatelessWidget {
  const BUddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BUddy',
      theme: ThemeData(
        primaryColor: DESIGN_ACCENT,
        scaffoldBackgroundColor: DESIGN_BACKGROUND,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme)
            .apply(
              bodyColor: DESIGN_PRIMARY_TEXT,
              displayColor: DESIGN_PRIMARY_TEXT,
            ),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: DESIGN_ACCENT,
          secondary: DESIGN_ACCENT,
        ),
      ),
      home: const SplashScreen(), // Start with the splash screen.
    );
  }
}
