import 'dart:async'; // For asynchronous operations like StreamSubscription.
import 'dart:ui'; // Required for ImageFilter.blur.
import 'package:flutter/material.dart'; // Flutter's core UI library.
import 'package:google_fonts/google_fonts.dart'; // For using custom fonts.
import 'package:flutter_spinkit/flutter_spinkit.dart'; // For the typing indicator animation.

import 'main.dart'; // For theme colors
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
  StreamSubscription? _typingSubscription;

  bool _initializing = true; // True while the bot connection is being set up.
  bool _isBotTyping = false; // True if the bot is "typing".

  @override
  void initState() {
    super.initState();
    _initBotpress(); // Start the bot connection process.
  }

  @override
  void dispose() {
    // --- Cancel subscriptions and dispose the service ---
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _botService.dispose(); // This closes the WebSocket connection.

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
      _typingSubscription = _botService.typingStream.listen(_onBotTyping);
    } catch (e) {
      if (mounted) _showError('Init error: $e');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  // Handles bot typing status updates.
  void _onBotTyping(bool isTyping) {
    if (mounted) {
      setState(() {
        _isBotTyping = isTyping;
      });
      if (isTyping) _scrollToBottom(); // Scroll down to show indicator
    }
  }

  // Handles new messages received from the bot.
  void _onBotMessageReceived(ChatMessage message) {
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

    // Add the user's message to the UI immediately.
    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
    );
    setState(() {
      _messages.add(userMessage);
    });
    _scrollToBottom();
    _textController.clear();

    // Send the message to the API.
    try {
      final ok = await _botService.sendTextMessage(text);
      if (!ok) {
        _showError('Failed to send message');
      }
      // The bot's reply will arrive via the stream listener.
    } catch (e) {
      _showError('Send error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DESIGN_BACKGROUND,
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
                        GRADIENT_START.withOpacity(0.6),
                        GRADIENT_MID.withOpacity(0.6),
                        GRADIENT_END.withOpacity(0.6),
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
                ? const Center(
                    child: CircularProgressIndicator(color: DESIGN_ACCENT),
                  )
                : Column(
                    children: [
                      // --- Header: Logo and Title ---
                      const SizedBox(height: 16),
                      const Icon(
                        Icons.auto_awesome,
                        color: DESIGN_ACCENT,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ask BUddy anything',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: DESIGN_PRIMARY_TEXT,
                        ),
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
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  return _buildMessageBubble(message);
                                },
                              ),
                      ),

                      // --- Typing Indicator ---
                      if (_isBotTyping) _buildTypingIndicator(),

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
                color: DESIGN_SECONDARY_TEXT,
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
    return GestureDetector(
      onTap: () {
        _textController.text = text;
        _handleSendPressed(); // Send the suggestion text as a message.
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: DESIGN_USER_BUBBLE.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: DESIGN_PRIMARY_TEXT,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Builds a single chat bubble for a message.
  Widget _buildMessageBubble(ChatMessage message) {
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
              color: DESIGN_SECONDARY_TEXT,
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
                color: message.isUser ? DESIGN_USER_BUBBLE : DESIGN_AI_BUBBLE,
                borderRadius: BorderRadius.circular(16),
                border: message.isUser
                    ? null
                    : Border.all(color: DESIGN_AI_BORDER),
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
                  color: DESIGN_PRIMARY_TEXT,
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
              color: DESIGN_SECONDARY_TEXT,
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
                color: DESIGN_AI_BUBBLE,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: DESIGN_AI_BORDER),
                boxShadow: const [
                  BoxShadow(
                    offset: Offset(0, 2),
                    blurRadius: 3.0,
                    color: Colors.black12,
                  ),
                ],
              ),
              // The 3-dot bounce animation.
              child: const SpinKitThreeBounce(color: DESIGN_ACCENT, size: 20.0),
            ),
          ),
        ],
      ),
    );
  }

  // Builds the text input field and send button at the bottom.
  Widget _buildTextInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      color: Colors.transparent,
      child: Container(
        // The white, rounded input bar.
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30.0),
          border: Border.all(color: DESIGN_AI_BORDER),
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
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: DESIGN_PRIMARY_TEXT,
                ),
                decoration: InputDecoration(
                  hintText: 'Ask me anything about student affairs',
                  hintStyle: GoogleFonts.inter(color: DESIGN_SECONDARY_TEXT),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(left: 20, right: 12),
                ),
                onSubmitted: (_) => _handleSendPressed(),
              ),
            ),
            // Send button.
            IconButton(
              icon: const Icon(Icons.near_me_outlined, color: DESIGN_ACCENT),
              onPressed: _handleSendPressed,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
