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
import '../utils/finance_classifier_parser.dart';
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

  /// Transport readiness: endpoint compiled in + a signed-in user. Independent
  /// of the [enabled] opt-in toggle — the finance Quick Add classifier uses
  /// this so Bedrock is the default ledger parser even when Cloud AI is off.
  bool get _hasTransport => _endpoint.isNotEmpty && tokenProvider() != null;

  @override
  bool get isAvailable => _hasTransport && _enabled;

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
    Map<String, dynamic> payload, {
    bool requireOptIn = true,
  }) async {
    // Most ops gate on the Cloud AI opt-in; the finance classifier only needs
    // transport (it's on by default — see [runFinanceClassifierStep]).
    if (requireOptIn ? !isAvailable : !_hasTransport) return null;
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
      return 'HTTP ${response.statusCode}: $body';
    } catch (e) {
      return 'error: $e';
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

    final body = jsonEncode({
      'op': 'respond',
      'payload': {
        'context': _contextToJson(context),
        'messages': messages
            .where((m) => m.role != AiChatRole.assistant || m.text.isNotEmpty)
            .map((m) => {
                  'role': m.role == AiChatRole.user ? 'user' : 'assistant',
                  'text': m.text,
                })
            .toList(),
      },
    });

    http.Response response;
    try {
      response = await http
          .post(Uri.parse(_endpoint), headers: _headers, body: body)
          .timeout(const Duration(seconds: _timeoutSeconds));
    } catch (e) {
      // Transport-level failure: no connection, DNS, or the request timed out
      // before any response. The only case where "check your connection" is
      // the honest diagnosis.
      debugPrint('CloudAiCoachService[respond] network error: $e');
      throw const AiCoachException(
          'Cloud coach unreachable. Check your connection and try again.');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiCoachException(
          'Your session has expired. Sign in again to use the cloud coach.');
    }
    if (response.statusCode == 429) {
      throw const AiCoachException(
          'The cloud coach hit its daily limit. Try again tomorrow.');
    }
    if (response.statusCode != 200) {
      // Reached the backend, but it errored (5xx, unhandled op, …). The
      // connection is fine — do NOT tell the user to check it.
      debugPrint('CloudAiCoachService[respond] '
          'server error HTTP ${response.statusCode}: ${response.body}');
      throw const AiCoachException(
          'The cloud coach had a hiccup on our end. Try again in a moment.');
    }

    final String text;
    try {
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      text = (result['response'] as String?) ?? '';
    } catch (e) {
      // 200 OK but the body wasn't the JSON shape we expected.
      debugPrint('CloudAiCoachService[respond] parse error: $e');
      throw const AiCoachException(
          'The cloud coach sent back something unreadable. Try again.');
    }
    yield text;
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

  // ── Parse food from image (Plan 029) ──────────────────────────────────────

  @override
  Future<PhotoParseResult> parseFoodFromImage(
    Uint8List imageBytes,
    String mimeType,
    String? caption,
  ) async {
    if (!isAvailable) {
      return const PhotoParseResult(PhotoParseStatus.unavailable);
    }

    final payload = <String, dynamic>{
      'image_base64': base64Encode(imageBytes),
      'mime_type': mimeType,
      if (caption != null && caption.trim().isNotEmpty)
        'caption': caption.trim(),
    };

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_endpoint),
            headers: _headers,
            body: jsonEncode({'op': 'parseFoodFromImage', 'payload': payload}),
          )
          .timeout(const Duration(seconds: _timeoutSeconds));
    } catch (e) {
      // Transport-level failure: no connection, DNS, or the request timed out
      // before any response. This is the genuine "check your connection" case.
      debugPrint('CloudAiCoachService[parseFoodFromImage] network error: $e');
      return PhotoParseResult(PhotoParseStatus.networkError, detail: '$e');
    }

    // The server enforces the per-user daily cap (Plan 034 SEV-1) and returns
    // 429 when it's reached — surface that distinctly so the UI can explain it.
    if (response.statusCode == 429) {
      return const PhotoParseResult(PhotoParseStatus.rateLimited);
    }
    if (response.statusCode != 200) {
      // Reached the backend, but it errored (5xx, auth, unhandled op, …). The
      // connection is fine — do NOT tell the user to check it.
      final bodySnippet = response.body.length > 300
          ? '${response.body.substring(0, 300)}…'
          : response.body;
      debugPrint('CloudAiCoachService[parseFoodFromImage] '
          'server error HTTP ${response.statusCode}: $bodySnippet');
      return PhotoParseResult(
        PhotoParseStatus.serverError,
        httpStatus: response.statusCode,
        detail: bodySnippet,
      );
    }

    try {
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final intentStr = result['intent'] as String?;
      if (intentStr == 'no_food') {
        return const PhotoParseResult(PhotoParseStatus.noFood);
      }
      final items = _photoItemsFromJson(result['items'] as List<dynamic>?);
      if (items.isEmpty) {
        return const PhotoParseResult(PhotoParseStatus.noFood);
      }
      return PhotoParseResult(
        PhotoParseStatus.ok,
        items: items,
        intent: ParseFoodResult.intentFromJson(intentStr),
      );
    } catch (e) {
      // 200 OK but the body wasn't the JSON shape we expected.
      debugPrint('CloudAiCoachService.parseFoodFromImage parse error: $e');
      return PhotoParseResult(PhotoParseStatus.failed, detail: '$e');
    }
  }

  /// Map the Lambda's `items` array into [ExtractedFoodItem]s. Photo items
  /// always carry a null `food_id` and a populated macro estimate.
  List<ExtractedFoodItem> _photoItemsFromJson(List<dynamic>? rawItems) {
    final parsed = <ExtractedFoodItem>[];
    for (final raw in (rawItems ?? const []).cast<Map<String, dynamic>>()) {
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
      parsed.add(ExtractedFoodItem(
        name: name,
        grams: (raw['grams'] as num?)?.toDouble() ?? 100,
        hydeDescription: (raw['hyde'] as String?) ?? '',
        rawText: name,
        resolvedFoodId: null, // photo items never resolve to a DB row
        resolverConfidence: (raw['confidence'] as num?)?.toDouble() ?? 0.0,
        estimatedMacros: macros,
        macroFallback: raw['macro_fallback'] as bool? ?? false,
      ));
    }
    return parsed;
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

  // ── Finance classifier (Bedrock Haiku via the `classifyFinance` op) ───────

  @override
  Future<ClassifierStep?> runFinanceClassifierStep({
    required List<LedgerChatTurn> conversation,
    required PreparseResult preparse,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required int turnCount,
  }) async {
    // Bedrock is the default Quick Add classifier regardless of the Cloud AI
    // opt-in toggle, but it still needs the endpoint + a signed-in user. Bail
    // to the next tier (on-device, then the form) when transport is missing.
    if (!_hasTransport) return null;

    // Hard turn budget — mirror the on-device tier so the clarify loop can't
    // burn the daily Bedrock cap.
    if (turnCount >= kMaxFinanceClarifyTurns) {
      return StepGiveUp(
        reason: 'Took too many tries — opening the form.',
        partialDraft: preparse.toDraft(),
      );
    }

    // Only top-level, active accounts are loggable via chat (Plan 026 §4) —
    // same filter the on-device tier and parser use.
    final activeAccounts = accounts
        .where((a) => a.isActive && !a.isSubAccount && !a.isCustodian)
        .toList();

    final prompt = buildFinanceClassifierPrompt(
      conversation: conversation,
      preparse: preparse,
      categories: categories,
      accounts: activeAccounts,
      learnedMappings: learnedMappings,
    );

    // Returns null on any transport/Bedrock error → the presenter falls back to
    // the on-device model, then the form. requireOptIn:false → runs without the
    // Cloud AI toggle.
    final result =
        await _call('classifyFinance', {'prompt': prompt}, requireOptIn: false);
    final text = result?['text'] as String?;
    if (text == null || text.isEmpty) return null;

    return parseFinanceClassifierResponse(
      text: text,
      accounts: activeAccounts,
      categories: categories,
      preparse: preparse,
    );
  }

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
