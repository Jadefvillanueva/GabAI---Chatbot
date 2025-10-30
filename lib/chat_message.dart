// A data model for a single chat message.
class ChatMessage {
  final String text;
  final bool
  isUser; // True if the message is from the user, false if from the AI.
  final String id; // Unique message ID to prevent duplicates.

  ChatMessage({required this.text, this.isUser = true, required this.id});
}
