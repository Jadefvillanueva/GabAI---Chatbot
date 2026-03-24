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
  static const String _kUserKeyPref = 'botpress_user_key';
  static const String _kUserIdPref = 'botpress_user_id';
  static const String _kConversationIdPref = 'botpress_conversation_id';

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

  /// Initialize: Create User -> Create/Get Conversation -> Start Polling.
  /// Returns true only when startup completes successfully.
  Future<bool> initialize() async {
    if (WEBHOOK_ID.isEmpty) {
      debugPrint('ERROR: BOTPRESS_WEBHOOK_ID is missing in .env');
      return false;
    }

    try {
      // 1. Create or Load User
      await _getOrCreateUser();

      // 2. Create or Load Conversation
      await _getOrCreateConversation();

      // 3. Treat existing Botpress history as already seen so the UI can
      // remain local-first and only show new live messages from now on.
      await _primeProcessedIdsFromHistory();

      // 4. Start Polling for new messages
      _startPolling();

      debugPrint('Botpress Chat API Initialized. User: $_userId');
      return true;
    } catch (e) {
      debugPrint('Initialization failed: $e');
      return false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _messageStreamController.close();
  }

  /// Polls the server every 2 seconds for new messages
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
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

            final payload = msg['payload'];
            final payloadMap = payload is Map
                ? Map<String, dynamic>.from(payload)
                : <String, dynamic>{};
            final senderId = msg['userId'].toString();
            final isUser = senderId == _userId;

            // Detect choice / dropdown payloads and media payloads.
            final String msgType = (payloadMap['type'] ?? 'text').toString();
            List<ChoiceOption>? options;
            String text = '';
            String? imageUrl;
            String? mediaTitle;

            if ((msgType == 'choice' || msgType == 'dropdown') &&
                payloadMap['options'] is List) {
              text = (payloadMap['text'] ?? '').toString();
              options = (payloadMap['options'] as List)
                  .map(
                    (o) => ChoiceOption(
                      label: (o['label'] ?? '').toString(),
                      value: (o['value'] ?? '').toString(),
                    ),
                  )
                  .toList();
            } else if (msgType == 'image') {
              imageUrl = _firstNonEmptyString(payloadMap, const ['imageUrl']);
              mediaTitle = _firstNonEmptyString(payloadMap, const [
                'title',
                'caption',
                'alt',
              ]);
              text = mediaTitle ?? 'Image';
            } else if (msgType == 'markdown') {
              text = (payloadMap['markdown'] ?? '').toString();
            } else {
              text =
                  (payloadMap['text'] ??
                          payloadMap['markdown'] ??
                          payloadMap['title'] ??
                          '')
                      .toString();

              // Fallback: handle image URLs even when payload type is missing.
              imageUrl = _firstNonEmptyString(payloadMap, const [
                'imageUrl',
                'image',
                'url',
              ]);
              mediaTitle ??= _firstNonEmptyString(payloadMap, const [
                'title',
                'caption',
                'alt',
              ]);
              if (imageUrl != null && text.trim().isEmpty) {
                text = mediaTitle ?? 'Image';
              }
            }

            if (text.trim().isEmpty && imageUrl == null) {
              text = 'Media message';
            }

            final normalizedType = options != null
                ? msgType
                : (imageUrl != null ? 'image' : 'text');

            _messageStreamController.add(
              ChatMessage(
                text: text,
                isUser: isUser,
                id: id,
                type: normalizedType,
                imageUrl: imageUrl,
                mediaTitle: mediaTitle,
                options: options,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Polling error: $e');
    }
  }

  String? _firstNonEmptyString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }

      // Some channels may nest URL data in an object.
      if (value is Map) {
        final nested = value['url'];
        if (nested is String && nested.trim().isNotEmpty) {
          return nested.trim();
        }
      }
    }
    return null;
  }

  Future<void> _primeProcessedIdsFromHistory() async {
    final conversationId = _conversationId;
    if (conversationId == null || _userKey == null) return;

    try {
      final url = Uri.parse('$API_URL/conversations/$conversationId/messages');
      final res = await http.get(
        url,
        headers: {'Content-Type': 'application/json', 'x-user-key': _userKey!},
      );

      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body);
      final List messages = json['messages'] ?? [];
      for (final msg in messages) {
        final id = msg['id']?.toString();
        if (id != null && id.isNotEmpty) {
          _processedMessageIds.add(id);
        }
      }
    } catch (e) {
      debugPrint('History priming skipped: $e');
    }
  }

  Future<void> _getOrCreateUser() async {
    // Ideally, check SharedPreferences here first to see if we already have a key
    final prefs = await SharedPreferences.getInstance();
    final storedUserKey = prefs.getString(_kUserKeyPref);
    final storedUserId = prefs.getString(_kUserIdPref);

    if (storedUserKey != null && storedUserId != null) {
      _userKey = storedUserKey;
      _userId = storedUserId;
      debugPrint('Restored existing user: $_userId');
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
      await prefs.setString(_kUserKeyPref, _userKey!);
      await prefs.setString(_kUserIdPref, _userId!);
    } else {
      throw 'Failed to create user: ${res.body}';
    }
  }

  Future<void> _getOrCreateConversation() async {
    final prefs = await SharedPreferences.getInstance();
    final storedConversationId = prefs.getString(_kConversationIdPref);

    if (storedConversationId != null) {
      _conversationId = storedConversationId;

      if (await _isConversationStillValid(storedConversationId)) {
        debugPrint('Restored existing conversation: $_conversationId');
        return;
      }

      await prefs.remove(_kConversationIdPref);
      _conversationId = null;
    }

    await _createConversation();
  }

  Future<bool> _isConversationStillValid(String conversationId) async {
    try {
      final url = Uri.parse('$API_URL/conversations/$conversationId/messages');
      final res = await http.get(
        url,
        headers: {'Content-Type': 'application/json', 'x-user-key': _userKey!},
      );

      // Explicitly invalid / inaccessible conversation IDs.
      if (res.statusCode == 401 ||
          res.statusCode == 403 ||
          res.statusCode == 404) {
        debugPrint('Stored conversation is invalid (${res.statusCode}).');
        return false;
      }

      // For transient server/network issues, keep the stored ID.
      return true;
    } catch (e) {
      debugPrint('Conversation validation skipped due to network error: $e');
      return true;
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kConversationIdPref, _conversationId!);
    } else {
      throw 'Failed to create conversation: ${res.body}';
    }
  }

  Future<void> sendTextMessage(String text) async {
    if (_conversationId == null || _userKey == null) {
      _messageStreamController.add(
        ChatMessage(
          text: 'Something went wrong, please try again later.',
          isUser: false,
          id: 'err-${DateTime.now().millisecondsSinceEpoch}',
          isError: true,
        ),
      );
      return;
    }

    final url = Uri.parse('$API_URL/messages');

    final body = jsonEncode({
      "conversationId": _conversationId,
      "payload": {"type": "text", "text": text},
      "type": "text",
    });

    try {
      final res = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'x-user-key': _userKey!,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 400) {
        debugPrint('Send failed (${res.statusCode}): ${res.body}');
        _messageStreamController.add(
          ChatMessage(
            text: 'Something went wrong, please try again later.',
            isUser: false,
            id: 'err-${DateTime.now().millisecondsSinceEpoch}',
            isError: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      _messageStreamController.add(
        ChatMessage(
          text: 'Something went wrong, please try again later.',
          isUser: false,
          id: 'err-${DateTime.now().millisecondsSinceEpoch}',
          isError: true,
        ),
      );
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
