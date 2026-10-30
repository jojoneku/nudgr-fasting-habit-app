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
    this.interruptedTools = const [],
    this.usage,
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

  /// Tools the model was in the middle of calling when the server's time
  /// budget ended the hop. Their input never finished, so they are not in
  /// [toolCalls]; the client asks for them again on a fresh hop. Only sent
  /// when the request opted in with `resume_cut_tools`.
  final List<String> interruptedTools;

  /// The user's AI usage today, as the server reported it with this reply.
  /// Null from a server that does not send it.
  final AdvisorUsage? usage;

  /// True when this turn is a request to run tools rather than an answer.
  bool get wantsTools => toolCalls.isNotEmpty;

  factory AdvisorReply.fromJson(Map<String, Object?> json) => AdvisorReply(
        text: (json['response'] as String?) ?? '',
        truncated: (json['truncated'] as bool?) ?? false,
        interruptedTools: [
          for (final t in (json['interrupted_tools'] as List?) ?? const [])
            if (t is String && t.isNotEmpty) t,
        ],
        toolCalls: [
          for (final c in (json['tool_calls'] as List?) ?? const [])
            if (c is Map) AiToolCall.fromJson(Map<String, Object?>.from(c)),
        ],
        assistantContent: [
          for (final b in (json['assistant_content'] as List?) ?? const [])
            if (b is Map) Map<String, Object?>.from(b),
        ],
        usage: AdvisorUsage.fromJson(json['ai_usage']),
      );
}

/// The user's AI usage that comes with an advisor reply (Plan 065, phase 5).
///
/// Nothing shows it yet. It is here so a usage screen can read it later.
class AdvisorUsage {
  const AdvisorUsage({this.count, required this.cap, this.costUsd});

  /// AI requests today, this message included. Null on a tool-loop hop
  /// (the server counts each message once) and when the server does not
  /// count at all.
  final int? count;

  /// AI requests allowed per day.
  final int cap;

  /// Estimated cost of this one model call, in USD, at list prices. Null for
  /// a model the server has no price for.
  final double? costUsd;

  /// Null when [json] is not a usage object with a whole-number cap.
  static AdvisorUsage? fromJson(Object? json) {
    if (json is! Map) return null;
    final cap = json['cap'];
    if (cap is! int) return null;
    final count = json['count'];
    final cost = json['cost_usd'];
    return AdvisorUsage(
      count: count is int ? count : null,
      cap: cap,
      costUsd: cost is num ? cost.toDouble() : null,
    );
  }
}
