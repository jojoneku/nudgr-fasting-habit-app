// Haiku routing for Nudgy (Plan 065, phase 5).
//
// A conversation picks its model once, from its first message, and keeps it:
// each model writes its own prompt cache, so a route that changed turn by
// turn would pay for two caches of the same history. Only a lookup goes to
// Haiku. Anything that plans, asks for advice or reads like a change goes to
// Sonnet, and so does anything unclear: a lookup sent to Sonnet costs a few
// cents, while a plan sent to Haiku costs answer quality.

import '../models/advisor_route.dart';
import '../models/ai_tool.dart';
import 'planning_intent.dart';

/// "How much" and "how many" ask for a figure, so they do not count as the
/// planning word "how".
final _figureQuestion = RegExp(r'\bhow\s+(much|many)\b', caseSensitive: false);

/// Words that ask for a change, or for advice rather than a figure.
final _writeOrAdviceWords = RegExp(
  r'\b(add|log|record|create|delete|remove|edit|change|update|set|rename|'
  r'move|transfer|mark|pay|cancel|undo|split|afford|advice|advise|recommend|'
  r'suggest|why|review|analy[sz]e|compare|explain|help|improve|optimi[sz]e|'
  r'cut|reduce)\b',
  caseSensitive: false,
);

/// The route for a conversation whose first message is [text].
///
/// Haiku only for a lookup: no planning word (the quick-log veto list), no
/// write or advice word, and no image (a photo of a bill or an offer needs
/// the advisor model to read it).
AdvisorRoute routeForFirstMessage(String text, {required bool hasImages}) {
  if (hasImages || text.trim().isEmpty) return AdvisorRoute.sonnet;
  if (_writeOrAdviceWords.hasMatch(text)) return AdvisorRoute.sonnet;
  if (hasPlanningIntent(text.replaceAll(_figureQuestion, ' '))) {
    return AdvisorRoute.sonnet;
  }
  return AdvisorRoute.haiku;
}

/// Why [input] does not fit [tool]'s schema, or null when it fits.
///
/// Checks the top level only: every `required` key is present, each known
/// property has its JSON type, and an `enum` property holds one of its values.
/// The executor still checks each call in full; this is the signal that the
/// routing model is not coping, so the conversation moves to Sonnet.
String? toolInputProblem(AiTool tool, Map<String, Object?> input) {
  final schema = tool.inputSchema;
  final required = schema['required'];
  if (required is List) {
    for (final key in required) {
      if (input[key] == null) return '$key is required';
    }
  }
  final properties = schema['properties'];
  if (properties is! Map) return null;
  for (final entry in input.entries) {
    final spec = properties[entry.key];
    final value = entry.value;
    if (spec is! Map || value == null) continue;
    final type = spec['type'];
    final types = type is List ? type : [type];
    if (type != null && !types.any((t) => _hasJsonType(value, t))) {
      return '${entry.key} must be $type';
    }
    final allowed = spec['enum'];
    if (allowed is List && !allowed.contains(value)) {
      return '${entry.key} must be one of ${allowed.join(', ')}';
    }
  }
  return null;
}

bool _hasJsonType(Object value, Object? type) => switch (type) {
      'string' => value is String,
      'number' => value is num,
      'integer' => value is int || (value is double && value % 1 == 0),
      'boolean' => value is bool,
      'array' => value is List,
      'object' => value is Map,
      'null' => false,
      _ => true,
    };
