import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

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

  // Pulsing ring for loading state
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _initBotpress();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _botService.dispose();
    _typingTimeout?.cancel();
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
      if (mounted) setState(() => _initializing = false);
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

          // ---- Main UI ----
          SafeArea(
            child: _initializing
                ? _buildLoadingState(c, isDark)
                : Column(
                    children: [
                      _buildGlassHeader(theme, c, isDark),
                      Expanded(
                        child: _messages.isEmpty && !_isBotTyping
                            ? _buildEmptyState(c, isDark)
                            : _buildMessageList(c, isDark),
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
      child: SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing ring
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
            Icon(
              Icons.auto_awesome_rounded,
              color: isDark ? Colors.white : Colors.white,
              size: 32,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // GLASS HEADER
  // =========================================================================

  Widget _buildGlassHeader(ThemeProvider theme, AppThemeColors c, bool isDark) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: c.headerGlass,
            border: Border(bottom: BorderSide(color: c.headerBorder)),
          ),
          child: Row(
            children: [
              // Logo
              Container(
                width: 36,
                height: 36,
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
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              // Title
              Expanded(
                child: Text(
                  'BUddy',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 3,
                    color: isDark ? Colors.white : Colors.white,
                  ),
                ),
              ),
              // Theme toggle
              GestureDetector(
                onTap: () => theme.toggleTheme(),
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
            const SizedBox(height: 40),
            // Big icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.2),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.6)
                    : Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Ask me anything',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w300,
                letterSpacing: 1,
                color: isDark ? Colors.white : Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Here are some ideas to get started',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w300,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildChip('What can I ask you to do?', c, isDark),
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
        _textController.text = text;
        _handleSendPressed();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: c.chipBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.chipBorder),
            ),
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
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Text(
              isUser ? 'YOU' : 'BUddy',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          // Bubble
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
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
                        color: isUser
                            ? Colors.transparent
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.white.withValues(alpha: 0.3)),
                      ),
                    ),
                    child: Text(
                      message.text,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        color: isUser
                            ? (isDark ? Colors.black : const Color(0xFF1A1A2E))
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Text(
              'BUddy',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(20),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 20,
                ),
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
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
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
              borderRadius: BorderRadius.circular(28),
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
            child: Row(
              children: [
                const SizedBox(width: 20),
                Expanded(
                  child: TextField(
                    controller: _textController,
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: (_) => _handleSendPressed(),
                  ),
                ),
                const SizedBox(width: 8),
                // Gradient send button
                GestureDetector(
                  onTap: _handleSendPressed,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isDark
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFFFF8A50), Color(0xFF1E88E5)],
                            ),
                      color: isDark ? Colors.white : null,
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      color: isDark ? Colors.black : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
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
