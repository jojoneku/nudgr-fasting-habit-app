import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/ai_meal_estimate.dart';
import '../models/ai_parsed_food.dart';
import '../models/food_parse_result.dart';
import 'ai_coach_service.dart';

/// Cloud AI Coach — calls the AWS Lambda → Bedrock Claude Haiku endpoint.
///
/// Endpoint is configured at build time via:
///   flutter run --dart-define=AI_COACH_ENDPOINT=https://xxxx.execute-api.amazonaws.com/coach
///
/// Falls back gracefully when offline or endpoint not configured.
class CloudAiCoachService implements AiCoachService {
  static const _endpoint = String.fromEnvironment('AI_COACH_ENDPOINT');
  static const _timeoutSeconds = 30;

  @override
  AiCoachTier get tier => AiCoachTier.cloud;

  @override
  bool get isAvailable => _endpoint.isNotEmpty;

  @override
  int? get downloadProgress => null;

  @override
  Future<void> downloadModel({void Function(int progress)? onProgress}) async {
    // No-op — cloud tier requires no download.
  }

  @override
  void dispose() {}

  // ── Respond ───────────────────────────────────────────────────────────────

  @override
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  }) async* {
    if (!isAvailable) {
      yield 'Cloud AI Coach is not configured. '
          'Ask your developer to set AI_COACH_ENDPOINT.';
      return;
    }

    final payload = {
      'context': _contextToJson(context),
      'messages': messages
          .where((m) => m.role != AiChatRole.assistant || m.text.isNotEmpty)
          .map((m) => {
                'role': m.role == AiChatRole.user ? 'user' : 'assistant',
                'text': m.text,
              })
          .toList(),
    };

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: _timeoutSeconds));

      if (response.statusCode != 200) {
        yield 'Coach unavailable (${response.statusCode}). Try again later.';
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (decoded['response'] as String?) ?? '';
      yield text;
    } catch (e) {
      debugPrint('CloudAiCoachService.respond error: $e');
      yield 'Cloud coach unreachable. Check your connection and try again.';
    }
  }

  // ── Parse food ────────────────────────────────────────────────────────────

  @override
  Future<FoodParseResult?> parseFood(String description) async {
    // Cloud tier delegates food parsing to the on-device path.
    // No need to make a remote call just for NLP parsing.
    return null;
  }

  @override
  Future<AiMealEstimate?> estimateMacros(String description) async => null;

  @override
  Future<List<AiItemEstimate>?> estimateMacrosForItems(
          List<AiParsedFood> items) async =>
      null;

  @override
  Future<List<AiParsedFood>?> normalizeFoodInput(
          List<String> fragments) async =>
      null;

  // ── Internals ─────────────────────────────────────────────────────────────

  Map<String, dynamic> _contextToJson(AiCoachContext ctx) => {
        'entryPoint': ctx.entryPoint.name,
        'isFasting': ctx.isFasting,
        'fastingStreak': ctx.fastingStreak,
        'playerLevel': ctx.playerLevel,
        'playerXp': ctx.playerXp,
        'playerHp': ctx.playerHp,
        if (ctx.elapsedFastMinutes != null)
          'elapsedFastMinutes': ctx.elapsedFastMinutes,
        if (ctx.fastingGoalHours != null)
          'fastingGoalHours': ctx.fastingGoalHours,
        if (ctx.todayCalories != null) 'todayCalories': ctx.todayCalories,
        if (ctx.calorieGoal != null) 'calorieGoal': ctx.calorieGoal,
        if (ctx.todayProtein != null) 'todayProtein': ctx.todayProtein,
        if (ctx.todayCarbs != null) 'todayCarbs': ctx.todayCarbs,
        if (ctx.todayFat != null) 'todayFat': ctx.todayFat,
        if (ctx.monthBudget != null) 'monthBudget': ctx.monthBudget,
        if (ctx.monthSpent != null) 'monthSpent': ctx.monthSpent,
      };
}
