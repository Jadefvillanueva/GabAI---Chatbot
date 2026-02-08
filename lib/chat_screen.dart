import 'dart:async'; // For asynchronous operations like StreamSubscription.
import 'dart:ui'; // Required for ImageFilter.blur.
import 'package:flutter/material.dart'; // Flutter's core UI library.
import 'package:google_fonts/google_fonts.dart'; // For using custom fonts.
import 'package:flutter_spinkit/flutter_spinkit.dart'; // For the typing indicator animation.

import 'theme_provider.dart'; // For theme colors
import 'chat_message.dart'; // For the message model
import 'botpress_service.dart'; // For the API service

// The main chat screen widget.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final BotpressService _botService = BotpressService(); // The API service
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = []; // List of all messages in the chat.
  final Set<String> _seenMessageIds =
      {}; // Tracks message IDs to avoid duplicates.

  // --- Stream Subscriptions (replaces Timer) ---
  StreamSubscription? _messageSubscription;

  bool _initializing = true; // True while the bot connection is being set up.
  bool _isBotTyping = false; // True if the bot is "typing".
  Timer? _typingTimeout;

  @override
  void initState() {
    super.initState();
    _initBotpress(); // Start the bot connection process.
  }

  @override
  void dispose() {
    // --- Cancel subscriptions and dispose the service ---
    _messageSubscription?.cancel();
    _botService.dispose(); // This closes the WebSocket connection.
    _typingTimeout?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Animates the scroll position to the bottom of the list.
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

  // Initializes the connection to Botpress and starts listening to streams.
  Future<void> _initBotpress() async {
    try {
      // 1. Initialize the Botpress service.
      await _botService.initialize();

      // 2. Listen to the message and typing streams.
      _messageSubscription = _botService.messageStream.listen(
        _onBotMessageReceived,
      );
    } catch (e) {
      if (mounted) _showError('Init error: $e');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  // Handles new messages received from the bot.
  void _onBotMessageReceived(ChatMessage message) {
    if (message.isUser) return;

    // Skip duplicate messages.
    if (_seenMessageIds.contains(message.id)) return;

    if (mounted) {
      setState(() {
        _isBotTyping = false; // Bot is no longer typing.
        _messages.add(message);
        _seenMessageIds.add(message.id);
      });
      _scrollToBottom();
    }
  }

  // Adds an error message to the chat UI.
  void _showError(String message) {
    final botMessage = ChatMessage(
      text: 'Error: $message',
      isUser: false,
      id: 'err-${DateTime.now().millisecondsSinceEpoch}',
    );
    if (mounted) {
      setState(() {
        _isBotTyping = false; // Stop typing on error.
        _messages.add(botMessage);
      });
      _scrollToBottom();
    }
  }

  // Called when the user presses the send button.
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
        _messages.add(userMessage);
        _isBotTyping = true;
      });
    }
    _scrollToBottom();

    // // Send the message to the API.
    // try {
    //   final ok = await _botService.sendTextMessage(text);
    //   if (!ok) {
    //     _showError('Failed to send message');
    //   }
    //   // The bot's reply will arrive via the stream listener.
    // } catch (e) {
    //   _showError('Send error: $e');
    // }

    _textController.clear();
    _typingTimeout?.cancel();
    _typingTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _isBotTyping = false;
        });
      }
    });
    await _botService.sendTextMessage(
      text,
    ); // Just send it. The stream will update the UI.
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final c = theme.colors;

    return Scaffold(
      backgroundColor: c.background,
      // Use a Stack to layer the background gradient.
      body: Stack(
        children: [
          // Blurred gradient background.
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 100.0, sigmaY: 100.0),
                child: Container(
                  width: MediaQuery.of(context).size.width * 1.5,
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        c.gradientStart.withOpacity(0.6),
                        c.gradientMid.withOpacity(0.6),
                        c.gradientEnd.withOpacity(0.6),
                      ],
                      radius: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Main chat UI.
          SafeArea(
            child: _initializing
                ? Center(child: CircularProgressIndicator(color: c.accent))
                : Column(
                    children: [
                      // --- Header: Logo, Title, and Theme Toggle ---
                      const SizedBox(height: 16),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Centered logo + title
                          Column(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: c.accent,
                                size: 40,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ask BUddy anything',
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: c.primaryText,
                                ),
                              ),
                            ],
                          ),
                          // Theme toggle button (top-right)
                          Positioned(
                            right: 12,
                            top: 0,
                            child: IconButton(
                              icon: Icon(
                                theme.isDarkMode
                                    ? Icons.light_mode_rounded
                                    : Icons.dark_mode_rounded,
                                color: c.accent,
                              ),
                              tooltip: theme.isDarkMode
                                  ? 'Switch to Light Mode'
                                  : 'Switch to Dark Mode',
                              onPressed: () => theme.toggleTheme(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // --- Message List ---
                      Expanded(
                        child: _messages.isEmpty && !_isBotTyping
                            ? _buildEmptyState() // Show suggestions if chat is empty.
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                itemCount:
                                    _messages.length + (_isBotTyping ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (_isBotTyping &&
                                      index == _messages.length) {
                                    return _buildTypingIndicator();
                                  }
                                  final message = _messages[index];
                                  return _buildMessageBubble(message);
                                },
                              ),
                      ),

                      // --- Text Input Field ---
                      _buildTextInputBar(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Builds the widget shown when the chat list is empty.
  Widget _buildEmptyState() {
    final c = ThemeScope.of(context).colors;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Suggestions on what to ask BUddy',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.secondaryText,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip('What can I ask you to do?'),
                _buildSuggestionChip('How do I apply for financial aid?'),
                _buildSuggestionChip('What are the scholarship requirements?'),
                _buildSuggestionChip('How to join student organizations?'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Builds a single clickable suggestion chip.
  Widget _buildSuggestionChip(String text) {
    final c = ThemeScope.of(context).colors;
    return GestureDetector(
      onTap: () {
        _textController.text = text;
        _handleSendPressed(); // Send the suggestion text as a message.
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.userBubble.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: c.primaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Builds a single chat bubble for a message.
  Widget _buildMessageBubble(ChatMessage message) {
    final c = ThemeScope.of(context).colors;
    return Container(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: message.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // "ME" or "BUddy" label.
          Text(
            message.isUser ? 'ME' : 'BUddy',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: c.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          // The message bubble container.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: message.isUser ? c.userBubble : c.aiBubble,
                borderRadius: BorderRadius.circular(16),
                border: message.isUser ? null : Border.all(color: c.aiBorder),
                boxShadow: const [
                  BoxShadow(
                    offset: Offset(0, 2),
                    blurRadius: 3.0,
                    color: Colors.black12,
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: GoogleFonts.inter(
                  color: c.primaryText,
                  fontSize: 16,
                  height: 1.4, // Line height for readability.
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Builds the "BUddy is typing" animation.
  Widget _buildTypingIndicator() {
    final c = ThemeScope.of(context).colors;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "BUddy" label.
          Text(
            'BUddy',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: c.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          // The bubble containing the animation.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: c.aiBubble,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.aiBorder),
                boxShadow: const [
                  BoxShadow(
                    offset: Offset(0, 2),
                    blurRadius: 3.0,
                    color: Colors.black12,
                  ),
                ],
              ),
              // The 3-dot bounce animation.
              child: SpinKitThreeBounce(color: c.accent, size: 20.0),
            ),
          ),
        ],
      ),
    );
  }

  // Builds the text input field and send button at the bottom.
  Widget _buildTextInputBar() {
    final c = ThemeScope.of(context).colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      color: Colors.transparent,
      child: Container(
        // The rounded input bar.
        decoration: BoxDecoration(
          color: c.inputBarBackground,
          borderRadius: BorderRadius.circular(30.0),
          border: Border.all(color: c.aiBorder),
          boxShadow: const [
            BoxShadow(
              offset: Offset(0, 4),
              blurRadius: 10.0,
              color: Colors.black12,
            ),
          ],
        ),
        child: Row(
          children: [
            // Text field.
            Expanded(
              child: TextField(
                controller: _textController,
                style: GoogleFonts.inter(fontSize: 16, color: c.primaryText),
                decoration: InputDecoration(
                  hintText: 'Ask me anything about student affairs',
                  hintStyle: GoogleFonts.inter(color: c.secondaryText),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(left: 20, right: 12),
                ),
                onSubmitted: (_) => _handleSendPressed(),
              ),
            ),
            // Send button.
            IconButton(
              icon: Icon(Icons.near_me_outlined, color: c.accent),
              onPressed: _handleSendPressed,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
