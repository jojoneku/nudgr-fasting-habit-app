import 'ai_chat_message.dart';

/// A single named Nudgy conversation — the unit the history browser
/// lists (ChatGPT/Claude style). Persisted locally and synced as part of the
/// advisor-state document.
class AdvisorConversation {
  /// Fixed id of the single overflow bucket that older chats fold into once the
  /// active-conversation cap is hit ("convert to what we had before").
  static const String archiveId = '__archive__';

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiChatMessage> messages;

  const AdvisorConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  bool get isArchive => id == archiveId;

  /// A short title derived from the first user message, or a fallback.
  static String titleFrom(List<AiChatMessage> messages) {
    for (final m in messages) {
      if (m.role == AiChatRole.user && m.text.trim().isNotEmpty) {
        final t = m.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        return t.length > 40 ? '${t.substring(0, 40)}…' : t;
      }
    }
    return 'New chat';
  }

  AdvisorConversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<AiChatMessage>? messages,
  }) =>
      AdvisorConversation(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );

  factory AdvisorConversation.fromJson(Map<String, dynamic> json) =>
      AdvisorConversation(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Chat',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        messages: (json['messages'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(AiChatMessage.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };
}
