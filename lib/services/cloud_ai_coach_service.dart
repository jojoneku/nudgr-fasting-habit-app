import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/ai_meal_estimate.dart';
import '../models/ai_parsed_food.dart';
import '../models/extracted_food_item.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/food_parse_result.dart';
import '../models/food_search_candidate.dart';
import 'ai_coach_service.dart';

/// Cloud AI Coach — calls the AWS Lambda → Bedrock Claude Haiku endpoint.
///
/// Endpoint configured at build time via:
///   flutter run --dart-define=AI_COACH_ENDPOINT=https://xxxx.execute-api.amazonaws.com/v1/coach
///
/// [tokenProvider] must return the current Supabase JWT (may be null when
/// signed out). The Lambda's JWT authorizer rejects calls without a valid
/// Bearer token, so all ops become no-ops when the token is absent.
class CloudAiCoachService implements AiCoachService {
  static const _endpoint = String.fromEnvironment('AI_COACH_ENDPOINT');
  static const _timeoutSeconds = 30;

  /// Returns the current Supabase access token, or null when signed out.
  final String? Function() tokenProvider;

  bool _enabled = false;

  /// Set to true when the user enables Cloud AI in Settings.
  set enabled(bool value) => _enabled = value;

  CloudAiCoachService({required this.tokenProvider});

  @override
  AiCoachTier get tier => AiCoachTier.cloud;

  @override
  bool get isAvailable =>
      _endpoint.isNotEmpty && _enabled && tokenProvider() != null;

  @override
  int? get downloadProgress => null;

  @override
  Future<void> downloadModel({void Function(int progress)? onProgress}) async {}

  @override
  void dispose() {}

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  Map<String, String> get _headers {
    final token = tokenProvider();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>?> _call(
    String op,
    Map<String, dynamic> payload,
  ) async {
    if (!isAvailable) return null;
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: _headers,
            body: jsonEncode({'op': op, 'payload': payload}),
          )
          .timeout(const Duration(seconds: _timeoutSeconds));

      if (response.statusCode != 200) {
        debugPrint(
            'CloudAiCoachService[$op] HTTP ${response.statusCode}: ${response.body}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('CloudAiCoachService[$op] error: $e');
      return null;
    }
  }

  // ── Respond (chat) ────────────────────────────────────────────────────────

  @override
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  }) async* {
    if (!isAvailable) {
      yield 'Cloud AI Coach is not configured. '
          'Sign in and enable Cloud AI in Settings.';
      return;
    }

    final result = await _call('respond', {
      'context': _contextToJson(context),
      'messages': messages
          .where((m) => m.role != AiChatRole.assistant || m.text.isNotEmpty)
          .map((m) => {
                'role': m.role == AiChatRole.user ? 'user' : 'assistant',
                'text': m.text,
              })
          .toList(),
    });

    if (result == null) {
      yield 'Cloud coach unreachable. Check your connection and try again.';
      return;
    }
    yield (result['response'] as String?) ?? '';
  }

  // ── Parse food ────────────────────────────────────────────────────────────

  @override
  Future<FoodParseResult?> parseFood(String description) async => null;

  // ── Extract food items ────────────────────────────────────────────────────

  @override
  Future<List<ExtractedFoodItem>?> extractFoodItems(String text) async {
    final result = await _call('extractFoodItems', {'text': text});
    if (result == null) return null;
    try {
      final items = result['items'] as List<dynamic>;
      return items
          .cast<Map<String, dynamic>>()
          .map(
            (item) => ExtractedFoodItem(
              name: item['name'] as String,
              grams: (item['grams'] as num?)?.toDouble() ?? 100,
              hydeDescription: (item['hyde'] as String?) ?? '',
              rawText: item['name'] as String,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('CloudAiCoachService.extractFoodItems parse error: $e');
      return null;
    }
  }

  // ── Estimate macros ───────────────────────────────────────────────────────

  @override
  Future<AiMealEstimate?> estimateMacros(String description) async {
    final result = await _call('estimateMacros', {'description': description});
    if (result == null) return null;
    try {
      final calories = (result['calories'] as num?)?.toInt() ?? 0;
      return AiMealEstimate(
        totalCalories: calories,
        confidence: 0.8,
        items: [
          AiItemEstimate(
            name: description,
            calories: calories,
            protein: (result['protein_g'] as num?)?.toDouble(),
            carbs: (result['carbs_g'] as num?)?.toDouble(),
            fat: (result['fat_g'] as num?)?.toDouble(),
          ),
        ],
      );
    } catch (e) {
      debugPrint('CloudAiCoachService.estimateMacros parse error: $e');
      return null;
    }
  }

  @override
  Future<List<AiItemEstimate>?> estimateMacrosForItems(
          List<AiParsedFood> items) async =>
      null;

  @override
  Future<List<AiParsedFood>?> normalizeFoodInput(
          List<String> fragments) async =>
      null;

  // ── Disambiguate food ─────────────────────────────────────────────────────

  @override
  Future<FoodDisambiguation?> disambiguateFood(
    String userQuery,
    List<FoodSearchCandidate> candidates,
  ) async {
    if (candidates.isEmpty) return null;
    final result = await _call('disambiguateFood', {
      'query': userQuery,
      'candidates': candidates
          .take(5)
          .map((c) => {'food_id': c.entry.id, 'name': c.entry.name})
          .toList(),
    });
    if (result == null) return null;
    final foodId = result['foodId'] as String?;
    final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
    if (foodId == null) return null;
    return FoodDisambiguation(foodId: foodId, confidence: confidence);
  }

  // ── Finance classifier (not implemented in cloud tier) ────────────────────

  @override
  Future<ClassifierStep?> runFinanceClassifierStep({
    required List<LedgerChatTurn> conversation,
    required PreparseResult preparse,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required int turnCount,
  }) async =>
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
