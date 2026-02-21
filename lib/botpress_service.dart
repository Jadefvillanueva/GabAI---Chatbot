import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'chat_message.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import this

class BotpressService {
  // Read the Webhook ID from .env
  static final String WEBHOOK_ID = dotenv.env['BOTPRESS_WEBHOOK_ID'] ?? '';
  static final String API_URL = 'https://chat.botpress.cloud/$WEBHOOK_ID';

  String? _userId;
  String? _userKey; // Required for authentication in Chat API
  String? _conversationId;

  // Stream to send messages to the UI
  final _messageStreamController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get messageStream => _messageStreamController.stream;

  // Polling timer
  Timer? _pollTimer;
  // Keep track of messages we've already sent to the UI to avoid duplicates
  final Set<String> _processedMessageIds = {};

  /// Initialize: Create User -> Create/Get Conversation -> Start Polling
  Future<void> initialize() async {
    if (WEBHOOK_ID.isEmpty) {
      debugPrint('ERROR: BOTPRESS_WEBHOOK_ID is missing in .env');
      return;
    }

    try {
      // 1. Create or Load User
      await _getOrCreateUser();

      // 2. Create or Load Conversation
      await _createConversation();

      // 3. Start Polling for new messages
      _startPolling();

      debugPrint('Botpress Chat API Initialized. User: $_userId');
    } catch (e) {
      debugPrint('Initialization failed: $e');
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _messageStreamController.close();
  }

  /// Polls the server every 2 seconds for new messages
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_conversationId != null && _userKey != null) {
        await _fetchNewMessages();
      }
    });
  }

  Future<void> _fetchNewMessages() async {
    // Capture the conversation ID before the async gap so we can detect
    // if a new conversation was started while this request was in-flight.
    final targetConversationId = _conversationId;
    try {
      final url = Uri.parse(
        '$API_URL/conversations/$targetConversationId/messages',
      );

      final res = await http.get(
        url,
        headers: {'Content-Type': 'application/json', 'x-user-key': _userKey!},
      );

      // If the conversation changed while we were waiting, discard results.
      if (_conversationId != targetConversationId) return;

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final List messages = json['messages'] ?? [];

        // Messages usually come newest first. Reverse to process oldest first.
        for (var msg in messages.reversed) {
          final id = msg['id'].toString();

          // If we haven't seen this message yet, add it to the stream
          if (!_processedMessageIds.contains(id)) {
            _processedMessageIds.add(id);

            final payload = msg['payload'] ?? {};
            final text = payload['text'] ?? 'Media message';
            final senderId = msg['userId'].toString();
            final isUser = senderId == _userId;

            _messageStreamController.add(
              ChatMessage(text: text, isUser: isUser, id: id),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Polling error: $e');
    }
  }

  Future<void> _getOrCreateUser() async {
    // Ideally, check SharedPreferences here first to see if we already have a key
    final prefs = await SharedPreferences.getInstance();
    final storedUserKey = prefs.getString('botpress_user_key');
    final storedUserId = prefs.getString('botpress_user_id');

    if (storedUserKey != null && storedUserId != null) {
      _userKey = storedUserKey;
      _userId = storedUserId;
      debugPrint("Restored existing user: $_userId");
      return;
    }

    // Create a new user if none exists
    final url = Uri.parse('$API_URL/users');

    // FIX: Explicitly send empty JSON body and Content-Type header
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _userId = data['user']['id'];
      _userKey =
          data['key']; // Use 'key', not 'user'['key'] based on some API versions

      // Save for next time
      await prefs.setString('botpress_user_key', _userKey!);
      await prefs.setString('botpress_user_id', _userId!);
    } else {
      throw 'Failed to create user: ${res.body}';
    }
  }

  Future<void> _createConversation() async {
    final url = Uri.parse('$API_URL/conversations');

    // FIX: Added Content-Type header here too
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'x-user-key': _userKey!},
      body: jsonEncode({}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _conversationId = data['conversation']['id'];
    } else {
      throw 'Failed to create conversation: ${res.body}';
    }
  }

  Future<void> sendTextMessage(String text) async {
    if (_conversationId == null || _userKey == null) return;

    final url = Uri.parse('$API_URL/messages');

    final body = jsonEncode({
      "conversationId": _conversationId,
      "payload": {"type": "text", "text": text},
      "type": "text",
    });

    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'x-user-key': _userKey!},
        body: body,
      );

      if (res.statusCode != 200) {
        debugPrint('Send failed: ${res.body}');
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  /// Start a fresh conversation (clears local tracking of old messages).
  Future<void> startNewConversation() async {
    // Stop polling so old messages aren't re-fetched while we reset.
    _pollTimer?.cancel();
    _processedMessageIds.clear();
    await _createConversation();
    // Resume polling against the new conversation.
    _startPolling();
  }
}
