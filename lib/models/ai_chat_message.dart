import 'dart:math';
import 'dart:typed_data';

enum AiChatRole { user, assistant }

class AiChatMessage {
  final String id;
  final AiChatRole role;
  final String text;
  final DateTime timestamp;

  /// True while the assistant is still streaming tokens into this message.
  final bool isStreaming;

  /// Optional attached image, shown in the user's bubble. In-memory only —
  /// deliberately NOT persisted (raw bytes would bloat storage) and never
  /// re-sent to the model on later turns; the image is sent once, on the turn
  /// it's attached.
  final Uint8List? imageBytes;

  /// Raw provider content blocks for this turn, used only by the tool loop:
  /// an assistant turn holding a `tool_use`, or a user turn carrying the
  /// matching `tool_result`.
  ///
  /// Kept verbatim rather than rebuilt from [text], because the `tool_use` ids
  /// inside are what pair a result with the call it answers — a reconstructed
  /// turn loses them. In-memory only and deliberately NOT persisted: a resumed
  /// conversation should not replay a half-finished tool loop, and the ids
  /// would be meaningless to a later turn anyway.
  final List<Map<String, Object?>> contentBlocks;

  const AiChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.isStreaming = false,
    this.imageBytes,
    this.contentBlocks = const [],
  });

  /// An assistant turn that asked to run tools. Carries the provider's blocks
  /// so the next hop can replay it exactly.
  factory AiChatMessage.assistantToolUse({
    required String text,
    required List<Map<String, Object?>> contentBlocks,
  }) =>
      AiChatMessage(
        id: _generateId(),
        role: AiChatRole.assistant,
        text: text,
        timestamp: DateTime.now(),
        contentBlocks: contentBlocks,
      );

  /// A user turn carrying tool results back to the model.
  factory AiChatMessage.toolResults(List<Map<String, Object?>> blocks) =>
      AiChatMessage(
        id: _generateId(),
        role: AiChatRole.user,
        text: '',
        timestamp: DateTime.now(),
        contentBlocks: blocks,
      );

  static String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  factory AiChatMessage.user(String text, {Uint8List? imageBytes}) =>
      AiChatMessage(
        id: _generateId(),
        role: AiChatRole.user,
        text: text,
        timestamp: DateTime.now(),
        imageBytes: imageBytes,
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
        imageBytes: imageBytes,
        contentBlocks: contentBlocks,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiChatMessage && id == other.id && text == other.text;

  @override
  int get hashCode => Object.hash(id, text);
}
