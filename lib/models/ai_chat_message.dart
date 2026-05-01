import 'dart:math';

enum AiChatRole { user, assistant }

class AiChatMessage {
  final String id;
  final AiChatRole role;
  final String text;
  final DateTime timestamp;

  /// True while the assistant is still streaming tokens into this message.
  final bool isStreaming;

  const AiChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.isStreaming = false,
  });

  static String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  factory AiChatMessage.user(String text) => AiChatMessage(
        id: _generateId(),
        role: AiChatRole.user,
        text: text,
        timestamp: DateTime.now(),
      );

  factory AiChatMessage.assistantStreaming() => AiChatMessage(
        id: _generateId(),
        role: AiChatRole.assistant,
        text: '',
        timestamp: DateTime.now(),
        isStreaming: true,
      );

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
        id: json['id'] as String,
        role: AiChatRole.values.byName(json['role'] as String),
        text: json['text'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  AiChatMessage copyWith({String? text, bool? isStreaming}) => AiChatMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiChatMessage && id == other.id && text == other.text;

  @override
  int get hashCode => Object.hash(id, text);
}
