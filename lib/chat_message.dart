/// A single option inside a choice / dropdown message.
class ChoiceOption {
  final String label;
  final String value;

  const ChoiceOption({required this.label, required this.value});

  Map<String, dynamic> toJson() {
    return {'label': label, 'value': value};
  }

  factory ChoiceOption.fromJson(Map<String, dynamic> json) {
    return ChoiceOption(
      label: (json['label'] ?? '').toString(),
      value: (json['value'] ?? '').toString(),
    );
  }
}

/// A data model for a single chat message.
class ChatMessage {
  final String text;
  final bool
  isUser; // True if the message is from the user, false if from the AI.
  final String id; // Unique message ID to prevent duplicates.
  final DateTime timestamp;
  final bool isError; // True if this is an error message.

  /// Message type – 'text', 'choice', 'dropdown', 'image', or 'file'.
  final String type;

  /// Image URL when [type] is 'image'.
  final String? imageUrl;

  /// File URL when [type] is 'file'.
  final String? fileUrl;

  /// Optional media title/caption provided by the payload.
  final String? mediaTitle;

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
    this.imageUrl,
    this.fileUrl,
    this.mediaTitle,
    this.options,
    this.isChoiceSelected = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'isUser': isUser,
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'isError': isError,
      'type': type,
      'imageUrl': imageUrl,
      'fileUrl': fileUrl,
      'mediaTitle': mediaTitle,
      'options': options?.map((o) => o.toJson()).toList(),
      'isChoiceSelected': isChoiceSelected,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    List<ChoiceOption>? parsedOptions;
    if (rawOptions is List) {
      parsedOptions = rawOptions
          .whereType<Map>()
          .map((o) => ChoiceOption.fromJson(Map<String, dynamic>.from(o)))
          .toList();
    }

    final rawTimestamp = (json['timestamp'] ?? '').toString();
    final parsedTimestamp = DateTime.tryParse(rawTimestamp);

    return ChatMessage(
      text: (json['text'] ?? '').toString(),
      isUser: json['isUser'] == true,
      id: (json['id'] ?? '').toString(),
      isError: json['isError'] == true,
      type: (json['type'] ?? 'text').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (json['imageUrl'] ?? '').toString().trim(),
      fileUrl: (json['fileUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (json['fileUrl'] ?? '').toString().trim(),
      mediaTitle: (json['mediaTitle'] ?? '').toString().trim().isEmpty
          ? null
          : (json['mediaTitle'] ?? '').toString().trim(),
      options: parsedOptions,
      isChoiceSelected: json['isChoiceSelected'] == true,
      timestamp: parsedTimestamp,
    );
  }
}
