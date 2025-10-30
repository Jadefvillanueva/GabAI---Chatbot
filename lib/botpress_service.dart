import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Data model for a chat message.
import 'chat_message.dart';

/// A service class to handle all interactions with the Botpress API.
class BotpressService {
  // The base URL for the Botpress chat API (for HTTP requests).
  // Read from the loaded environment variables
  static final String BASE_URL =
      dotenv.env['BOTPRESS_BASE_URL'] ?? 'MISSING_BASE_URL';
  // The WebSocket URL for real-time communication.
  static final String WEBSOCKET_URL =
      dotenv.env['BOTPRESS_WEBSOCKET_URL'] ?? 'MISSING_WSS_URL';

  String? _userId; // The Botpress user ID.
  String? _conversationId; // The ID for the current chat session.
  String? _userKey; // The authentication key for the user.

  // Public getter for the Botpress user ID.
  String? get userId => _userId;

  // --- WebSocket and Stream Controllers ---
  WebSocketChannel? _channel;
  final _messageStreamController = StreamController<ChatMessage>.broadcast();
  final _typingStreamController = StreamController<bool>.broadcast();

  // Public streams for the ChatScreen to listen to
  Stream<ChatMessage> get messageStream => _messageStreamController.stream;
  Stream<bool> get typingStream => _typingStreamController.stream;

  // Returns HTTP headers for requests that don't require authentication.
  Map<String, String> _baseHeaders() => {'Content-Type': 'application/json'};

  // Returns HTTP headers including the user's authentication key.
  Map<String, String> _authHeaders() => {
    'Content-Type': 'application/json',
    'x-user-key': _userKey ?? '',
  };

  /// Initializes the connection to Botpress by creating a user and conversation.
  Future<void> initialize() async {
    if (BASE_URL == 'MISSING_BASE_URL' || WEBSOCKET_URL == 'MISSING_WSS_URL') {
      throw 'Failed to load .env file. Make sure it exists and is loaded in main.dart';
    }

    // 1. Create a new user.
    final user = await _createUser();
    if (user != null) {
      _userId = user['id'];
      _userKey = user['key']; // Save the authentication key.
    } else {
      throw 'Failed to create user';
    }

    // 2. Create a new conversation.
    _conversationId = await _createConversation();

    if (_conversationId == null) {
      throw 'Failed to create conversation';
    }

    // 3. Connect to the WebSocket.
    _connectWebSocket();
  }

  /// Connects to the Botpress WebSocket and handles incoming events.
  void _connectWebSocket() {
    if (_userKey == null) {
      debugPrint('Cannot connect to WebSocket: missing user key');
      return;
    }

    // 1. Connect to the WebSocket server.
    _channel = WebSocketChannel.connect(Uri.parse(WEBSOCKET_URL));

    // 2. Send the authentication message.
    final authMessage = jsonEncode({
      'type': 'auth',
      'payload': {'key': _userKey},
    });
    _channel?.sink.add(authMessage);

    // 3. Listen for incoming messages.
    _channel?.stream.listen(
      _handleWebSocketEvent,
      onError: (error) {
        debugPrint('WebSocket Error: $error');
        // Reconnection logic could be added here.
      },
      onDone: () {
        debugPrint('WebSocket connection closed');
        // Reconnection logic could be added here.
      },
    );
  }

  /// Parses incoming WebSocket events and adds them to the correct stream.
  void _handleWebSocketEvent(dynamic data) {
    try {
      final event = jsonDecode(data);
      final type = event['type']?.toString() ?? '';

      switch (type) {
        case 'text':
          // A new text message from the bot.
          final id =
              event['id']?.toString() ??
              'ws-msg-${DateTime.now().millisecondsSinceEpoch}';
          final text = event['payload']?['text']?.toString() ?? '';

          if (text.isEmpty) return;

          final botMessage = ChatMessage(text: text, isUser: false, id: id);
          // Add the message to the stream.
          _messageStreamController.add(botMessage);
          break;

        case 'typing':
          // Bot typing status changed.
          final isTyping = event['payload']?['typing'] as bool? ?? false;
          _typingStreamController.add(isTyping);
          break;

        // Handle other event types as needed.
        default:
          debugPrint('Unhandled WebSocket event type: $type');
      }
    } catch (e) {
      debugPrint('Failed to parse WebSocket event: $e');
    }
  }

  // Calls the API to create a new Botpress user and get an auth key.
  Future<Map<String, String>?> _createUser() async {
    final url = Uri.parse('$BASE_URL/users');
    final body = jsonEncode({}); // Body is empty for the simplest user.

    final res = await http.post(url, headers: _baseHeaders(), body: body);

    if (res.statusCode == 201 || res.statusCode == 200) {
      final j = jsonDecode(res.body);
      final id = j['user']?['id']?.toString();
      final key = j['key']?.toString(); // Get the key from the response.

      if (id != null && key != null) {
        return {'id': id, 'key': key};
      }
      return null;
    } else {
      throw 'createUser failed: ${res.statusCode} ${res.body}';
    }
  }

  // Calls the API to create a new conversation session.
  Future<String?> _createConversation() async {
    if (_userKey == null) return null; // Requires auth key.
    final url = Uri.parse('$BASE_URL/conversations');
    final body = jsonEncode({'tags': {}});

    final res = await http.post(url, headers: _authHeaders(), body: body);

    if (res.statusCode == 201 || res.statusCode == 200) {
      final j = jsonDecode(res.body);
      final id = j['conversation']?['id']?.toString();
      return id;
    } else {
      throw 'createConversation failed: ${res.statusCode} ${res.body}';
    }
  }

  /// Sends a user's text message to the Botpress API via WebSocket.
  Future<bool> sendTextMessage(String text) async {
    if (_channel == null || _conversationId == null) {
      debugPrint('Missing channel or conversation id');
      return false;
    }

    // Send a 'text' message payload.
    final message = jsonEncode({
      'type': 'text',
      'payload': {'conversationId': _conversationId, 'text': text},
    });

    try {
      _channel?.sink.add(message);
      return true;
    } catch (e) {
      debugPrint('Failed to send WebSocket message: $e');
      return false;
    }
  }

  /// Closes WebSocket and stream controllers.
  void dispose() {
    _channel?.sink.close();
    _messageStreamController.close();
    _typingStreamController.close();
  }
}
