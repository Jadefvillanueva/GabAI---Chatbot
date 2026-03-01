import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'theme_provider.dart';
import 'chat_message.dart';
import 'botpress_service.dart';

// ---------------------------------------------------------------------------
// Chat Screen
// ---------------------------------------------------------------------------
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final BotpressService _botService = BotpressService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final Set<String> _seenMessageIds = {};

  // Animation controllers – one per message for staggered mount animations.
  final List<AnimationController> _messageAnimControllers = [];

  StreamSubscription? _messageSubscription;
  bool _initializing = true;
  bool _isBotTyping = false;
  Timer? _typingTimeout;
  bool _hasText = false;
  bool _showScrollToBottom = false;

  // Connectivity
  bool _isOnline = true;
  StreamSubscription? _connectivitySubscription;

  // Pulsing ring for loading state
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _textController.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
    _initConnectivity();
    _initBotpress();
  }

  Future<void> _initConnectivity() async {
    // Check initial connectivity
    final result = await Connectivity().checkConnectivity();
    _updateConnectivity(result);

    // Listen for changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _updateConnectivity,
    );
  }

  void _updateConnectivity(List<ConnectivityResult> result) {
    final online = result.any((r) => r != ConnectivityResult.none);
    if (online != _isOnline && mounted) {
      setState(() => _isOnline = online);
    }
  }

  void _stopPulseIfNotNeeded() {
    // Stop the infinite pulse animation when it's no longer visible
    if (!_initializing && _messages.isNotEmpty) {
      if (_pulseController.isAnimating) _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _messageSubscription?.cancel();
    _botService.dispose();
    _typingTimeout?.cancel();
    _textController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _textController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    for (final c in _messageAnimControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _initBotpress() async {
    try {
      await _botService.initialize();
      _messageSubscription = _botService.messageStream.listen(
        _onBotMessageReceived,
      );
    } catch (e) {
      if (mounted) _showError('Init error: $e');
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
        _stopPulseIfNotNeeded();
      }
    }
  }

  void _onBotMessageReceived(ChatMessage message) {
    if (message.isUser) return;
    if (_seenMessageIds.contains(message.id)) return;

    if (mounted) {
      setState(() {
        _isBotTyping = false;
        _addMessageWithAnimation(message);
        _seenMessageIds.add(message.id);
      });
      _scrollToBottom();
    }
  }

  void _addMessageWithAnimation(ChatMessage message) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _messageAnimControllers.add(controller);
    _messages.add(message);
    controller.forward();
    _stopPulseIfNotNeeded();
  }

  void _showError(String message) {
    final botMessage = ChatMessage(
      text: 'Error: $message',
      isUser: false,
      id: 'err-${DateTime.now().millisecondsSinceEpoch}',
    );
    if (mounted) {
      setState(() {
        _isBotTyping = false;
        _addMessageWithAnimation(botMessage);
      });
      _scrollToBottom();
    }
  }

  void _handleSendPressed() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();

    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
    );
    if (mounted) {
      setState(() {
        _addMessageWithAnimation(userMessage);
        _isBotTyping = true;
      });
    }
    _scrollToBottom();

    _textController.clear();
    _typingTimeout?.cancel();
    _typingTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _isBotTyping = false);
    });
    await _botService.sendTextMessage(text);
  }

  /// Handle when the user taps a choice option button.
  void _handleChoiceSelected(ChatMessage message, ChoiceOption option) async {
    if (message.isChoiceSelected) return;
    HapticFeedback.lightImpact();

    // Mark the choice as selected so the buttons become disabled.
    setState(() => message.isChoiceSelected = true);

    // Add the user's selection as a local user message.
    final userMessage = ChatMessage(
      text: option.label,
      isUser: true,
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
    );
    setState(() {
      _addMessageWithAnimation(userMessage);
      _isBotTyping = true;
    });
    _scrollToBottom();

    _typingTimeout?.cancel();
    _typingTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _isBotTyping = false);
    });

    // Send the value back to the bot as a regular text message.
    await _botService.sendTextMessage(option.value);
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow =
        _scrollController.offset <
        _scrollController.position.maxScrollExtent - 150;
    if (shouldShow != _showScrollToBottom && _messages.isNotEmpty) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Shows a styled confirmation dialog before starting a new conversation.
  Future<void> _showNewConversationDialog() async {
    HapticFeedback.mediumImpact();
    final theme = ThemeScope.of(context);
    final isDark = theme.isDarkMode;

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.82,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        offset: const Offset(0, 16),
                        blurRadius: 48,
                        color: Colors.black.withValues(alpha: 0.25),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'New Conversation',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Start fresh? Your current chat\nwill be cleared.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.6,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.45)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Buttons
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : const Color(0xFFF3F4F6),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : const Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Cancel',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop(true);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: isDark
                                      ? null
                                      : const LinearGradient(
                                          colors: [
                                            Color(0xFFFF8A50),
                                            Color(0xFFFF6D3A),
                                          ],
                                        ),
                                  color: isDark ? Colors.white : null,
                                  boxShadow: [
                                    BoxShadow(
                                      offset: const Offset(0, 4),
                                      blurRadius: 12,
                                      color: isDark
                                          ? Colors.transparent
                                          : const Color(
                                              0xFFFF8A50,
                                            ).withValues(alpha: 0.3),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    'Start New',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _handleNewConversation();
    }
  }

  Future<void> _handleNewConversation() async {
    // Stop polling and create new conversation FIRST, so no in-flight
    // fetches can sneak old messages back into the cleared UI.
    await _botService.startNewConversation();

    for (final c in _messageAnimControllers) {
      c.dispose();
    }
    if (mounted) {
      setState(() {
        _messageAnimControllers.clear();
        _messages.clear();
        _seenMessageIds.clear();
        _isBotTyping = false;
        _showScrollToBottom = false;
      });
    }
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final c = theme.colors;
    final isDark = theme.isDarkMode;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ---- Background gradient (light) or solid black (dark) ----
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Colors.black, Colors.black, Colors.black],
                    )
                  : const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        Color(0xFFFF8A50),
                        Color(0xFF64B5F6),
                        Color(0xFF1E88E5),
                      ],
                    ),
            ),
          ),

          // ---- Main UI ----
          SafeArea(
            child: _initializing
                ? _buildLoadingState(c, isDark)
                : Column(
                    children: [
                      _buildGlassHeader(theme, c, isDark),
                      Expanded(
                        child: Stack(
                          children: [
                            _messages.isEmpty && !_isBotTyping
                                ? _buildEmptyState(c, isDark)
                                : _buildMessageList(c, isDark),
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: IgnorePointer(
                                  ignoring: !_showScrollToBottom,
                                  child: AnimatedOpacity(
                                    opacity: _showScrollToBottom ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 200),
                                    child: AnimatedScale(
                                      scale: _showScrollToBottom ? 1.0 : 0.5,
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      curve: Curves.easeOutBack,
                                      child: _buildScrollToBottomButton(
                                        c,
                                        isDark,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildInputBar(c, isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // LOADING STATE — pulsing rings
  // =========================================================================

  Widget _buildLoadingState(AppThemeColors c, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulsing ring
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    final v = _pulseController.value;
                    return Transform.scale(
                      scale: 1.0 + v * 0.5,
                      child: Opacity(
                        opacity: (1 - v).clamp(0.0, 0.5),
                        child: Container(
                          width: 80,
                          height: 80,
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
                  builder: (context, _) {
                    final v = (_pulseController.value + 0.5) % 1.0;
                    return Transform.scale(
                      scale: 1.0 + v * 0.35,
                      child: Opacity(
                        opacity: (1 - v).clamp(0.0, 0.35),
                        child: Container(
                          width: 60,
                          height: 60,
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
                Image.asset(
                  'assets/logo.png',
                  width: 52,
                  height: 52,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final v = _pulseController.value;
              final opacity = v < 0.5 ? 0.3 + v * 1.0 : 0.3 + (1.0 - v) * 1.0;
              return Opacity(opacity: opacity.clamp(0.3, 0.8), child: child);
            },
            child: Text(
              'Connecting...',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w300,
                letterSpacing: 1.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // GLASS HEADER
  // =========================================================================

  Widget _buildGlassHeader(ThemeProvider theme, AppThemeColors c, bool isDark) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: c.headerGlass,
            border: Border(bottom: BorderSide(color: c.headerBorder)),
          ),
          child: Row(
            children: [
              // Logo with online indicator
              Stack(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.2),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isOnline
                            ? const Color(0xFF34D399)
                            : Colors.grey,
                        border: Border.all(
                          color: isDark
                              ? Colors.black
                              : (_isOnline
                                    ? const Color.fromARGB(255, 17, 165, 96)
                                    : Colors.grey.shade700),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Title + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'BUddy',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _isOnline ? 'Online' : 'Offline',
                        key: ValueKey(_isOnline),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: _isOnline
                              ? const Color(0xFF34D399)
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // New conversation
              GestureDetector(
                onTap: _showNewConversationDialog,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.15),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Theme toggle
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  theme.toggleTheme();
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.15),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    theme.isDarkMode
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // EMPTY STATE — suggestion chips
  // =========================================================================

  Widget _buildEmptyState(AppThemeColors c, bool isDark) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            const SizedBox(height: 48),
            // Greeting icon with pulsing glow
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      final v = _pulseController.value;
                      return Transform.scale(
                        scale: 1.0 + v * 0.3,
                        child: Opacity(
                          opacity: (1 - v).clamp(0.0, 0.25),
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      Icons.waving_hand_rounded,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.white,
                      size: 36,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _getGreeting(),
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "I'm BUddy, your student helper.",
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w300,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try asking me anything:',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w300,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _buildChip('What can you help me with?', c, isDark),
                _buildChip('How do I apply for financial aid?', c, isDark),
                _buildChip('Scholarship requirements?', c, isDark),
                _buildChip('How to join student orgs?', c, isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String text, AppThemeColors c, bool isDark) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _textController.text = text;
        _handleSendPressed();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 11,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // MESSAGE LIST
  // =========================================================================

  Widget _buildMessageList(AppThemeColors c, bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: _messages.length + (_isBotTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isBotTyping && index == _messages.length) {
          return _buildTypingIndicator(c, isDark);
        }
        final message = _messages[index];
        final anim = _messageAnimControllers[index];
        return _AnimatedMessageBubble(
          animation: anim,
          child: _buildBubble(message, c, isDark),
        );
      },
    );
  }

  // =========================================================================
  // MESSAGE BUBBLE
  // =========================================================================

  Widget _buildBubble(ChatMessage message, AppThemeColors c, bool isDark) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Label
          Padding(
            padding: const EdgeInsets.only(bottom: 5, left: 6, right: 6),
            child: Text(
              isUser ? 'You' : 'BUddy',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          // Bubble
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              child: GestureDetector(
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  Clipboard.setData(ClipboardData(text: message.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Copied to clipboard',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: message.isError
                        ? (isDark
                              ? Colors.red.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.2))
                        : isUser
                        ? (isDark
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.9))
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.white.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 6),
                      bottomRight: Radius.circular(isUser ? 6 : 20),
                    ),
                    border: Border.all(
                      color: message.isError
                          ? Colors.red.withValues(alpha: 0.4)
                          : isUser
                          ? Colors.transparent
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.3)),
                    ),
                    boxShadow: isUser
                        ? [
                            BoxShadow(
                              offset: const Offset(0, 2),
                              blurRadius: 12,
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.2 : 0.08,
                              ),
                            ),
                          ]
                        : null,
                  ),
                  child: message.isError
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: isDark
                                  ? Colors.red.shade300
                                  : Colors.red.shade200,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                message.text,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  height: 1.5,
                                  color: isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade200,
                                ),
                              ),
                            ),
                          ],
                        )
                      : isUser
                      ? Text(
                          message.text,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                            color: isDark
                                ? Colors.black
                                : const Color(0xFF1A1A2E),
                          ),
                        )
                      : MarkdownBody(
                          data: message.text,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              height: 1.5,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.white,
                            ),
                            strong: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.white,
                            ),
                            em: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.white,
                            ),
                            code: GoogleFonts.firaCode(
                              fontSize: 13,
                              backgroundColor: isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.black.withValues(alpha: 0.1),
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.white,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            codeblockPadding: const EdgeInsets.all(12),
                            listBullet: GoogleFonts.inter(
                              fontSize: 15,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.white,
                            ),
                            a: GoogleFonts.inter(
                              fontSize: 15,
                              color: isDark
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFF90CAF9),
                              decoration: TextDecoration.underline,
                            ),
                            blockSpacing: 8,
                          ),
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              launchUrl(Uri.parse(href));
                            }
                          },
                        ),
                ),
              ),
            ),
          ),
          // Choice / dropdown option buttons
          if (!isUser && message.options != null && message.options!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.options!.map((opt) {
                  final disabled = message.isChoiceSelected;
                  return GestureDetector(
                    onTap: disabled
                        ? null
                        : () => _handleChoiceSelected(message, opt),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: disabled ? 0.45 : 1.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          opt.label,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.9)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          // Timestamp
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
            child: Text(
              _formatTimestamp(message.timestamp),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final hour = timestamp.hour;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final time = '$displayHour:$minute $period';

    // If today, show just the time
    if (timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day) {
      return time;
    }

    // If yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    if (timestamp.year == yesterday.year &&
        timestamp.month == yesterday.month &&
        timestamp.day == yesterday.day) {
      return 'Yesterday, $time';
    }

    // Otherwise show date
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[timestamp.month - 1]} ${timestamp.day}, $time';
  }

  // =========================================================================
  // TYPING INDICATOR
  // =========================================================================

  Widget _buildTypingIndicator(AppThemeColors c, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 5, left: 6, right: 6),
            child: Text(
              'BUddy',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.3),
              ),
            ),
            child: SpinKitThreeBounce(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // INPUT BAR — glassmorphism + gradient send button
  // =========================================================================

  Widget _buildInputBar(AppThemeColors c, bool isDark) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.08),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? c.inputBarBackground
                  : Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? c.inputBarBorder
                    : Colors.white.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, 4),
                  blurRadius: 20,
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 80,
                    maxHeight: 160,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ask me anything...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w300,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.35)
                              : const Color(0xFF9CA3AF),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                // Send button row
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: _hasText ? _handleSendPressed : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: _hasText && !isDark
                                ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFFF8A50),
                                      Color(0xFFFF6D3A),
                                    ],
                                  )
                                : null,
                            color: _hasText
                                ? (isDark ? Colors.white : null)
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.06)),
                            boxShadow: _hasText
                                ? [
                                    BoxShadow(
                                      offset: const Offset(0, 2),
                                      blurRadius: 8,
                                      color: isDark
                                          ? Colors.transparent
                                          : const Color(
                                              0xFFFF8A50,
                                            ).withValues(alpha: 0.3),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            color: _hasText
                                ? (isDark ? Colors.black : Colors.white)
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : Colors.black.withValues(alpha: 0.2)),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // SCROLL TO BOTTOM BUTTON
  // =========================================================================

  Widget _buildScrollToBottomButton(AppThemeColors c, bool isDark) {
    return GestureDetector(
      onTap: _scrollToBottom,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, 2),
              blurRadius: 12,
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            ),
          ],
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: isDark
              ? Colors.white.withValues(alpha: 0.7)
              : const Color(0xFF1A1A2E),
          size: 24,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated Message Wrapper — opacity + slide-up on mount
// ---------------------------------------------------------------------------
class _AnimatedMessageBubble extends AnimatedWidget {
  final Widget child;

  const _AnimatedMessageBubble({
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final anim = listenable as Animation<double>;
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
    return Opacity(
      opacity: curved.value,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - curved.value)),
        child: child,
      ),
    );
  }
}
