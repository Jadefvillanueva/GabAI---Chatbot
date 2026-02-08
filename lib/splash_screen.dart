import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_screen.dart'; // Import the chat screen
import 'theme_provider.dart'; // Import for theme colors

// The splash screen shown on app launch.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Animation that scales from 1.2 down to 1.0.
    _animation = Tween<double>(
      begin: 1.2,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    // Navigate to the chat screen after 2 seconds.
    Timer(const Duration(seconds: 2), _navigateToHome);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Replaces the splash screen with the chat screen.
  void _navigateToHome() {
    Navigator.of(context).pushReplacement(_createRoute());
  }

  // Defines the slide-up page transition animation.
  Route _createRoute() {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const ChatScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0); // Start from bottom.
        const end = Offset.zero; // End at center.
        const curve = Curves.easeOut;
        var tween = Tween(
          begin: begin,
          end: end,
        ).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        // Apply the scale animation to the logo and title.
        child: ScaleTransition(
          scale: _animation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo icon.
              Icon(Icons.auto_awesome, color: c.accent, size: 80),
              const SizedBox(height: 20),
              // App title.
              Text(
                'BUddy Student Helper',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: c.primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
