import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_screen.dart';
import 'theme_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Logo scale-in
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    // Pulsing ring
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // Text fade-in (delayed)
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _scaleController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _fadeController.forward();
    });

    Timer(const Duration(seconds: 3), _navigateToHome);
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(_createRoute());
  }

  Route _createRoute() {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const ChatScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 600),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final isDark = theme.isDarkMode;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // -- Full gradient background --
          Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        Color(0xFFFF8A50),
                        Color(0xFF64B5F6),
                        Color(0xFF1E88E5),
                      ],
                    ),
              color: isDark ? Colors.black : null,
            ),
          ),

          // -- Centered content --
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing rings + logo
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer pulsing ring
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final value = _pulseController.value;
                            return Transform.scale(
                              scale: 1.0 + value * 0.4,
                              child: Opacity(
                                opacity: (1 - value).clamp(0.0, 0.4),
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.6),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        // Inner pulsing ring (offset phase)
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final value = (_pulseController.value + 0.5) % 1.0;
                            return Transform.scale(
                              scale: 1.0 + value * 0.3,
                              child: Opacity(
                                opacity: (1 - value).clamp(0.0, 0.3),
                                child: Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        // Frosted logo container
                        ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.white.withValues(alpha: 0.25),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                color: isDark ? Colors.white : Colors.white,
                                size: 42,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Title
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(_fadeAnimation),
                    child: Column(
                      children: [
                        Text(
                          'BUddy',
                          style: GoogleFonts.inter(
                            fontSize: 36,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 6,
                            color: isDark ? Colors.white : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'STUDENT HELPER',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 4,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
