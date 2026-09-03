import 'ai_tool.dart';

/// One turn of the advisor's reply.
///
/// Replaces the bare `String` the advisor used to return. That was always
/// slightly a fiction — the cloud advisor is a single blocking call that
/// yielded exactly once — and a tool loop makes it untenable: the client has
/// to know whether the model asked for a tool before it can decide whether the
/// turn is over.
class AdvisorReply {
  const AdvisorReply({
    this.text = '',
    this.toolCalls = const [],
    this.assistantContent = const [],
    this.truncated = false,
  });

  /// The prose half of the turn. May be empty when the model went straight to
  /// a tool call, and may sit alongside tool calls when it did both.
  final String text;

  /// Tools the model asked to run. Empty on an ordinary answer.
  final List<AiToolCall> toolCalls;

  /// The assistant turn exactly as the model produced it, kept verbatim so the
  /// next hop can replay it. It must not be rebuilt from [text] and
  /// [toolCalls]: a reconstructed turn loses the `tool_use` ids that results
  /// have to pair with, and the model then cannot match them up.
  final List<Map<String, Object?>> assistantContent;

  /// The reply hit its token ceiling and stopped early.
  final bool truncated;

  /// True when this turn is a request to run tools rather than an answer.
  bool get wantsTools => toolCalls.isNotEmpty;

  factory AdvisorReply.fromJson(Map<String, Object?> json) => AdvisorReply(
        text: (json['response'] as String?) ?? '',
        truncated: (json['truncated'] as bool?) ?? false,
        toolCalls: [
          for (final c in (json['tool_calls'] as List?) ?? const [])
            if (c is Map) AiToolCall.fromJson(Map<String, Object?>.from(c)),
        ],
        assistantContent: [
          for (final b in (json['assistant_content'] as List?) ?? const [])
            if (b is Map) Map<String, Object?>.from(b),
        ],
      );
}
