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
/// signed out). The API Gateway JWT authorizer rejects unauthenticated calls
/// with 401, so all ops become no-ops when the token is absent.
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

  /// Returns a raw diagnostic string: HTTP status + first 200 chars of body.
  /// Only used by [NutritionPresenter.debugTestCloudAi].
  Future<String> debugPing(String op, Map<String, dynamic> payload) async {
    if (!isAvailable) {
      return 'isAvailable=false  token=${tokenProvider() != null}';
    }
    final tokenInfo = _tokenDiagnostic();
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: _headers,
            body: jsonEncode({'op': op, 'payload': payload}),
          )
          .timeout(const Duration(seconds: _timeoutSeconds));
      final body = response.body.length > 200
          ? '${response.body.substring(0, 200)}…'
          : response.body;
      return 'HTTP ${response.statusCode}: $body\n$tokenInfo';
    } catch (e) {
      return 'error: $e\n$tokenInfo';
    }
  }

  /// Debug-only: decode the JWT header + the claims the API Gateway authorizer
  /// checks (alg, kid, iss, aud, exp). Never decodes or logs the signature.
  String _tokenDiagnostic() {
    final token = tokenProvider();
    if (token == null) return 'token=null';
    final parts = token.split('.');
    if (parts.length != 3) return 'token malformed (parts=${parts.length})';
    String decodeSeg(String seg) {
      var s = seg.replaceAll('-', '+').replaceAll('_', '/');
      while (s.length % 4 != 0) {
        s += '=';
      }
      return utf8.decode(base64.decode(s));
    }

    try {
      final header = jsonDecode(decodeSeg(parts[0])) as Map<String, dynamic>;
      final claims = jsonDecode(decodeSeg(parts[1])) as Map<String, dynamic>;
      final exp = claims['exp'];
      final expStr = exp is int
          ? DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true)
              .toIso8601String()
          : '$exp';
      return 'token: alg=${header['alg']} kid=${header['kid']} '
          'iss=${claims['iss']} aud=${claims['aud']} exp=$expStr';
    } catch (e) {
      return 'token decode error: $e';
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
  // Cloud path always uses parseFoodWithCandidates — this op is unreachable.

  @override
  Future<List<ExtractedFoodItem>?> extractFoodItems(String text) async => null;

  // ── Parse food with candidates (Plan 026) ────────────────────────────────

  @override
  Future<ParseFoodResult?> parseFoodWithCandidates(
    String text,
    List<FoodSearchCandidate> candidates,
  ) async {
    final result = await _call('parseFoodWithCandidates', {
      'text': text,
      'candidates': candidates
          .take(15)
          .map((c) => {
                'food_id': c.entry.id,
                'name': c.entry.name,
                'cal_per_100g': c.entry.caloriesPer100g,
                if (c.entry.proteinPer100g != null)
                  'protein_per_100g': c.entry.proteinPer100g,
                if (c.entry.carbsPer100g != null)
                  'carbs_per_100g': c.entry.carbsPer100g,
                if (c.entry.fatPer100g != null)
                  'fat_per_100g': c.entry.fatPer100g,
              })
          .toList(),
    });
    if (result == null) return null;
    try {
      final rawItems = result['items'] as List<dynamic>;
      final parsed = <ExtractedFoodItem>[];
      for (final raw in rawItems.cast<Map<String, dynamic>>()) {
        final name = (raw['name'] as String?) ?? '';
        if (name.isEmpty) continue;
        final macrosJson = raw['estimated_macros'] as Map<String, dynamic>?;
        final macros = macrosJson == null
            ? null
            : EstimatedMacros(
                calories: (macrosJson['calories'] as num?)?.toDouble() ?? 0,
                proteinG: (macrosJson['protein_g'] as num?)?.toDouble() ?? 0,
                carbsG: (macrosJson['carbs_g'] as num?)?.toDouble() ?? 0,
                fatG: (macrosJson['fat_g'] as num?)?.toDouble() ?? 0,
              );
        // For single-item parses, preserve the user's original phrasing
        // (e.g. "100g plain fried chicken") as the chip label. For multi-item
        // parses we have no per-item source span, so the AI-normalized name is
        // the best we can do.
        final rawText = rawItems.length == 1 ? text : name;
        parsed.add(ExtractedFoodItem(
          name: name,
          grams: (raw['grams'] as num?)?.toDouble() ?? 100,
          hydeDescription: (raw['hyde'] as String?) ?? '',
          rawText: rawText,
          resolvedFoodId: raw['food_id'] as String?,
          resolverConfidence: (raw['confidence'] as num?)?.toDouble() ?? 0.0,
          estimatedMacros: macros,
          macroFallback: raw['macro_fallback'] as bool? ?? false,
        ));
      }
      return ParseFoodResult(
        items: parsed,
        intent: ParseFoodResult.intentFromJson(result['intent'] as String?),
      );
    } catch (e) {
      debugPrint('CloudAiCoachService.parseFoodWithCandidates parse error: $e');
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
