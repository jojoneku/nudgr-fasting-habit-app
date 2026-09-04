/// Tool-calling primitives for the Nudgy finance agent.
///
/// These are model-facing types, not an MCP client. MCP is a protocol for
/// reaching tools *across* processes; every tool here is an in-process Dart
/// call on data that never leaves the device, so there is nothing for it to
/// bridge today.
///
/// The catalogue is nonetheless kept MCP-shaped, and [toMcpJson] proves it
/// rather than asserting it. MCP describes a tool with exactly the same trio —
/// name, description, JSON Schema — plus behaviour annotations, so the only
/// real differences are key casing (`inputSchema` vs Bedrock's `input_schema`)
/// and how a result is wrapped. Both are encoded below. If Nudgy ever grows a
/// second consumer — a desktop client, or tools hosted outside the app — the
/// catalogue is already the right shape and only the transport is new.
library;

/// What a tool does to stored data.
///
/// Deliberately not a single `mutates` bool: MCP annotates behaviour along
/// three independent axes, and collapsing them loses the distinction between
/// "changes something" and "destroys something" — which is exactly the
/// distinction the confirm cards are built around.
enum AiToolKind {
  /// Reads only. Safe to execute on arrival with no confirmation.
  read,

  /// Adds a row. Undone by a delete.
  create,

  /// Changes an existing row. Undone by editing back.
  update,

  /// Removes a row. Undone by nothing — the strongest confirmation.
  destroy;

  /// True when executing this would change stored data. A mutating call is
  /// never executed on arrival; it becomes a proposal the user confirms.
  bool get mutates => this != AiToolKind.read;

  bool get readOnlyHint => this == AiToolKind.read;
  bool get destructiveHint => this == AiToolKind.destroy;

  /// Re-running with identical arguments lands in the same state. A `create`
  /// is not idempotent: run twice, you have two rows.
  bool get idempotentHint =>
      this == AiToolKind.read || this == AiToolKind.update;
}

/// One tool the model may call.
class AiTool {
  const AiTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.kind,
  });

  final String name;

  /// Shown to the model. This is the only thing telling it *when* to reach for
  /// the tool, so it carries the when, not just the what.
  final String description;

  /// JSON Schema for the tool's arguments.
  ///
  /// Two rules hold across the catalogue and are asserted in tests: no schema
  /// may expose `applyToFuture` (recurrence scope is the user's choice on the
  /// confirm card, never the model's), and no schema may take an entity id
  /// except one obtained from a `find*` result.
  final Map<String, Object?> inputSchema;

  final AiToolKind kind;

  bool get mutates => kind.mutates;

  /// Bedrock / Anthropic Messages API shape: snake_case `input_schema`, and
  /// behaviour is not expressed — the model infers it from the description.
  Map<String, Object?> toRequestJson() => {
        'name': name,
        'description': description,
        'input_schema': inputSchema,
      };

  /// MCP `tools/list` shape: camelCase `inputSchema`, behaviour carried
  /// explicitly in `annotations`.
  Map<String, Object?> toMcpJson() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
        'annotations': {
          'readOnlyHint': kind.readOnlyHint,
          'destructiveHint': kind.destructiveHint,
          'idempotentHint': kind.idempotentHint,
        },
      };
}

/// A `tool_use` block the model returned.
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.input,
  });

  /// Bedrock's `tool_use.id`. The matching result must echo it back, or the
  /// model cannot pair the result with the call it made.
  final String id;
  final String name;
  final Map<String, Object?> input;

  factory AiToolCall.fromJson(Map<String, Object?> json) => AiToolCall(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        input: Map<String, Object?>.from(
            (json['input'] as Map?) ?? const <String, Object?>{}),
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'input': input};
}

/// The outcome of a tool call, sent back to the model.
///
/// This describes what ACTUALLY happened, never what was proposed. A user who
/// declines a confirm card produces a result saying so; returning a success
/// here would have the model narrate a save that never occurred, which is the
/// exact failure advisor rule 8 exists to prevent.
class AiToolResult {
  const AiToolResult({
    required this.toolUseId,
    required this.ok,
    required this.summary,
  });

  /// The user declined a proposed mutation. Not an error: the tool worked, the
  /// answer was no.
  factory AiToolResult.declined(String toolUseId) => AiToolResult(
        toolUseId: toolUseId,
        ok: false,
        summary: 'The user declined this change. Nothing was saved. Do not '
            'retry the same proposal — ask what they would prefer instead.',
      );

  factory AiToolResult.failed(String toolUseId, String reason) =>
      AiToolResult(toolUseId: toolUseId, ok: false, summary: reason);

  final String toolUseId;
  final bool ok;
  final String summary;

  factory AiToolResult.fromJson(Map<String, Object?> json) => AiToolResult(
        toolUseId: (json['tool_use_id'] as String?) ?? '',
        ok: (json['ok'] as bool?) ?? false,
        summary: (json['summary'] as String?) ?? '',
      );

  Map<String, Object?> toJson() => {
        'tool_use_id': toolUseId,
        'ok': ok,
        'summary': summary,
      };

  /// The content block replayed to Bedrock on the next hop.
  Map<String, Object?> toContentBlock() => {
        'type': 'tool_result',
        'tool_use_id': toolUseId,
        'content': summary,
        if (!ok) 'is_error': true,
      };

  /// MCP `tools/call` result shape. Same information, different wrapper:
  /// content is a typed list and the failure flag is `isError`.
  Map<String, Object?> toMcpJson() => {
        'content': [
          {'type': 'text', 'text': summary}
        ],
        'isError': !ok,
      };
}
