/// A single option inside a choice / dropdown message.
class ChoiceOption {
  final String label;
  final String value;

  const ChoiceOption({required this.label, required this.value});
}

/// A data model for a single chat message.
class ChatMessage {
  final String text;
  final bool
  isUser; // True if the message is from the user, false if from the AI.
  final String id; // Unique message ID to prevent duplicates.
  final DateTime timestamp;
  final bool isError; // True if this is an error message.

  /// Message type – 'text', 'choice', or 'dropdown'.
  final String type;

  /// Options available when [type] is 'choice' or 'dropdown'.
  final List<ChoiceOption>? options;

  /// Whether the user has already picked one of the [options].
  bool isChoiceSelected;

  ChatMessage({
    required this.text,
    this.isUser = true,
    required this.id,
    this.isError = false,
    this.type = 'text',
    this.options,
    this.isChoiceSelected = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
