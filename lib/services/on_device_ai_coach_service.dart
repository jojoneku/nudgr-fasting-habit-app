import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

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
import '../utils/food_nlp_parser.dart';
import '../utils/food_unit_converter.dart';
import 'ai_coach_service.dart';

/// On-device AI Coach powered by Qwen3 0.6B via flutter_gemma.
///
/// Model: https://huggingface.co/litert-community/Qwen3-0.6B (~586 MB)
/// Format: .litertlm (LiteRT-LM engine — Android + iOS)
///
/// Two inference modes:
///   - Food parsing  → isThinking: false, low temperature (fast, deterministic JSON)
///   - Coaching      → isThinking: true,  higher temperature (full reasoning)
class OnDeviceAiCoachService implements AiCoachService {
  static const _modelUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm';

  final Future<String?> Function()? tokenProvider;

  OnDeviceAiCoachService({this.tokenProvider});

  InferenceModel? _model;
  bool _isDownloading = false;
  int _downloadProgress = 0;
  bool _deviceIncompatible = false;

  // ── LRU caches (in-memory only, reset on app restart) ─────────────────────
  static const _cacheSize = 50;
  final LinkedHashMap<String, List<AiParsedFood>?> _normalizeCache =
      LinkedHashMap();
  final LinkedHashMap<String, List<AiItemEstimate>?> _macroForItemsCache =
      LinkedHashMap();
  final LinkedHashMap<String, ClassifierStep?> _financeClassifierCache =
      LinkedHashMap();

  @override
  AiCoachTier get tier => AiCoachTier.onDevice;

  @override
  bool get isAvailable => _model != null && !_deviceIncompatible;

  bool get isDeviceIncompatible => _deviceIncompatible;

  @override
  int? get downloadProgress => _isDownloading ? _downloadProgress : null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call once at app start — silently loads model if already installed.
  Future<void> init() async {
    await FlutterGemma.initialize();
    if (!FlutterGemma.hasActiveModel()) return;
    await _loadModel();
  }

  @override
  Future<void> downloadModel({void Function(int progress)? onProgress}) async {
    if (_isDownloading) return;
    _isDownloading = true;
    _downloadProgress = 0;

    try {
      final token = await tokenProvider?.call();
      await FlutterGemma.initialize(huggingFaceToken: token);

      if (FlutterGemma.hasActiveModel()) {
        await _loadModel();
        return;
      }

      await FlutterGemma.installModel(
        modelType: ModelType.qwen,
        fileType: ModelFileType.task,
      ).fromNetwork(_modelUrl, token: token).withProgress((p) {
        _downloadProgress = p;
        onProgress?.call(p);
      }).install();

      await _loadModel();
    } finally {
      _isDownloading = false;
    }
  }

  Future<void> _loadModel() async {
    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.gpu,
      );
    } catch (gpuError) {
      try {
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 4096,
          preferredBackend: PreferredBackend.cpu,
        );
      } catch (cpuError) {
        final msg = cpuError.toString().toLowerCase();
        if (msg.contains('opencl') ||
            msg.contains('can not find') ||
            msg.contains('litert')) {
          _deviceIncompatible = true;
          debugPrint('OnDeviceAiCoachService: device incompatible — $cpuError');
        } else {
          debugPrint('OnDeviceAiCoachService: model load failed: $cpuError');
        }
      }
    }
  }

  @override
  void dispose() {
    _model = null;
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  V? _cacheGet<K, V>(LinkedHashMap<K, V> cache, K key) {
    final v = cache.remove(key);
    if (v != null) cache[key] = v;
    return v;
  }

  void _cachePut<K, V>(LinkedHashMap<K, V> cache, K key, V value) {
    cache.remove(key);
    cache[key] = value;
    while (cache.length > _cacheSize) {
      cache.remove(cache.keys.first);
    }
  }

  // ── Respond ───────────────────────────────────────────────────────────────

  @override
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  }) async* {
    final model = _model;
    if (model == null) {
      yield _unavailableMessage(context);
      return;
    }

    final chat = await model.createChat(
      temperature: isThinking ? 0.7 : 0.5,
      topK: isThinking ? 40 : 20,
      isThinking: isThinking,
      modelType: ModelType.qwen,
    );

    try {
      // Rebuild multi-turn context in the fresh session.
      // flutter_gemma has no systemInstruction param, so prepend the system
      // prompt to the first user message. Replay both user AND assistant turns
      // so the model has full conversation context.
      final systemContext = _buildSystemTurn(context);
      bool systemPrepended = false;

      for (final msg in messages) {
        if (msg.role == AiChatRole.user) {
          final text =
              systemPrepended ? msg.text : '$systemContext\n\n${msg.text}';
          systemPrepended = true;
          await chat.addQuery(Message(text: text, isUser: true));
        } else if (msg.text.isNotEmpty) {
          // Replay previous assistant responses to rebuild context.
          await chat.addQuery(Message(text: msg.text, isUser: false));
        }
      }

      if (!systemPrepended) {
        // Edge case: no user messages yet — send system context alone.
        await chat.addQuery(Message(text: systemContext, isUser: true));
      }

      // Stream tokens in real time. Think-block tokens (<think>…</think>)
      // are silently stripped so they never appear in chat. During the
      // thinking phase message.text stays empty → typing indicator shows.
      bool hasContent = false;
      await for (final token in _filterThinkTokens(
        chat.generateChatResponseAsync().timeout(
              const Duration(seconds: 90),
              onTimeout: (sink) => sink.close(),
            ),
      )) {
        hasContent = true;
        yield token;
      }

      if (!hasContent) {
        yield 'I could not generate a response. Please try again.';
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('opencl') ||
          msg.contains('can not find') ||
          msg.contains('litert')) {
        _deviceIncompatible = true;
        debugPrint('OnDeviceAiCoachService: device incompatible — $e');
        yield 'AI Coach is not supported on this device (missing OpenCL/GPU). '
            'The cloud coach may be available as a fallback.';
      } else {
        debugPrint('OnDeviceAiCoachService.respond error: $e');
        yield 'AI Coach encountered an error. Please try again.';
      }
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  // ── Parse food ────────────────────────────────────────────────────────────

  @override
  Future<FoodParseResult?> parseFood(String description) async {
    // Fast path: try rule-based parser first.
    final quick = FoodNlpParser.parse(description);
    if (quick.isNotEmpty && _allItemsHaveExactUnits(quick)) {
      return quick;
    }

    final model = _model;
    if (model == null) {
      // No model available — return best-effort rule-based result.
      return quick.isNotEmpty ? quick : null;
    }

    // Model path: ask Qwen3 to extract structured food items.
    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false, // Fast mode — no reasoning needed for parsing.
      modelType: ModelType.qwen,
    );

    try {
      await chat.addQuery(
        Message(text: '$_foodParsePrompt$description', isUser: true),
      );

      final response = await chat.generateChatResponse().timeout(
            const Duration(seconds: 30),
          );

      final text =
          response is TextResponse ? response.token : response.toString();

      return _parseFoodResponse(text, description);
    } catch (e) {
      debugPrint('OnDeviceAiCoachService.parseFood failed: $e');
      return quick.isNotEmpty ? quick : null;
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Strips `<think>…</think>` blocks and model-specific special tokens from
  /// a raw token stream.
  ///
  /// Qwen3 wraps its reasoning in `<think>…</think>` before the real answer,
  /// and may append end-of-sequence tokens like `<|im_end|>`. We silently
  /// discard both so users only see the clean final answer.
  Stream<String> _filterThinkTokens(Stream<ModelResponse> source) async* {
    // Regex matches any <|...|> special token (im_end, endoftext, etc.)
    final specialTokenRe = RegExp(r'<\|[^|>]+\|>');

    bool inThink = false;
    final buf = StringBuffer();

    await for (final resp in source) {
      if (resp is! TextResponse || resp.token.isEmpty) continue;
      buf.write(resp.token);

      // One incoming token can span multiple tag boundaries — loop until stable.
      while (true) {
        final text = buf.toString();
        if (!inThink) {
          final start = text.indexOf('<think>');
          if (start == -1) {
            // No opening tag — yield safe portion, keep a 7-char look-ahead
            // in case the tag arrives split across the next token.
            if (text.length > 7) {
              final safe = text.substring(0, text.length - 7);
              final cleaned = safe.replaceAll(specialTokenRe, '');
              if (cleaned.isNotEmpty) yield cleaned;
              buf
                ..clear()
                ..write(text.substring(text.length - 7));
            }
            break;
          }
          // Yield everything before the opening tag, then enter think mode.
          if (start > 0) {
            final before =
                text.substring(0, start).replaceAll(specialTokenRe, '');
            if (before.isNotEmpty) yield before;
          }
          inThink = true;
          buf
            ..clear()
            ..write(text.substring(start + 7)); // skip '<think>'
        } else {
          final end = text.indexOf('</think>');
          if (end == -1) {
            // Still inside thinking block — discard, keep 8-char look-ahead.
            if (text.length > 8) {
              buf
                ..clear()
                ..write(text.substring(text.length - 8));
            }
            break;
          }
          // Exit think mode and continue processing the remainder.
          inThink = false;
          buf
            ..clear()
            ..write(text.substring(end + 8)); // skip '</think>'
        }
      }
    }

    // Flush any buffered text that wasn't inside a think block.
    if (!inThink && buf.isNotEmpty) {
      final flushed = buf.toString().replaceAll(specialTokenRe, '').trim();
      if (flushed.isNotEmpty) yield flushed;
    }
  }

  bool _allItemsHaveExactUnits(FoodParseResult result) =>
      result.items.every((i) => !i.isEstimated);

  String _buildSystemTurn(AiCoachContext context) {
    final persona =
        _personas[context.entryPoint] ?? _personas[AiCoachEntryPoint.general]!;
    return '$persona\n\n${context.toPromptSummary()}\n\nRespond concisely. '
        'Do not repeat the stats back. Be direct and helpful.';
  }

  String _unavailableMessage(AiCoachContext context) =>
      switch (context.entryPoint) {
        AiCoachEntryPoint.nutrition =>
          'Download the AI Coach to unlock smart food analysis.',
        AiCoachEntryPoint.fasting =>
          'Download the AI Coach to get fasting phase guidance.',
        AiCoachEntryPoint.stats =>
          'Download the AI Coach to get RPG strategy advice.',
        AiCoachEntryPoint.treasury =>
          'Download the AI Coach to get finance insights.',
        AiCoachEntryPoint.general =>
          'AI Coach not downloaded. Tap "Download" to get started (~586 MB).',
      };

  FoodParseResult? _parseFoodResponse(String text, String original) {
    final match = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (match == null) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(match.group(0)!);
    } catch (_) {
      return null;
    }

    final rawItems = decoded as List<dynamic>;
    final items = <ParsedFoodItem>[];

    for (final raw in rawItems) {
      final map = raw as Map<String, dynamic>;
      final name = (map['name'] as String?)?.trim() ?? '';
      final grams = (map['grams'] as num?)?.toDouble();
      final unit = (map['unit'] as String?)?.toLowerCase();
      final qty = (map['quantity'] as num?)?.toDouble() ?? 1.0;

      if (name.isEmpty) continue;

      double resolvedGrams;
      bool estimated = false;

      if (grams != null && grams > 0) {
        resolvedGrams = grams;
      } else if (unit != null) {
        resolvedGrams =
            FoodUnitConverter.convert(qty, unit, foodName: name) ?? 100.0;
        estimated = !FoodUnitConverter.isExact(unit);
      } else {
        resolvedGrams = 100.0;
        estimated = true;
      }

      items.add(ParsedFoodItem(
        rawText: original,
        name: name,
        grams: resolvedGrams,
        isEstimated: estimated,
      ));
    }

    if (items.isEmpty) return null;
    return FoodParseResult(items: items, usedModel: true);
  }

  // ── Estimate macros ───────────────────────────────────────────────────────

  @override
  Future<AiMealEstimate?> estimateMacros(String description) async {
    final model = _model;
    if (model == null) return null;

    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false,
      modelType: ModelType.qwen,
    );

    try {
      await chat.addQuery(
        Message(text: '$_macroEstimatePrompt$description', isUser: true),
      );

      final response = await chat
          .generateChatResponse()
          .timeout(const Duration(seconds: 20));

      final text =
          response is TextResponse ? response.token : response.toString();

      return _parseMacroResponse(text, description);
    } catch (e) {
      debugPrint('OnDeviceAiCoachService.estimateMacros failed: $e');
      return null;
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  AiMealEstimate? _parseMacroResponse(String text, String description) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(match.group(0)!);
    } catch (_) {
      return null;
    }

    final json = decoded as Map<String, dynamic>;
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final items = rawItems.map((raw) {
      final item = raw as Map<String, dynamic>;
      final calories = (item['calories'] as num?)?.toInt() ?? 0;
      final protein = (item['protein'] as num?)?.toDouble();
      final carbs = (item['carbs'] as num?)?.toDouble();
      final fat = (item['fat'] as num?)?.toDouble();
      final (ep, ec, ef) = _fillMacros(calories, protein, carbs, fat);
      return AiItemEstimate(
        name: (item['name'] as String?) ?? description,
        calories: calories,
        protein: ep,
        carbs: ec,
        fat: ef,
      );
    }).toList();

    if (items.isEmpty) return null;
    return AiMealEstimate(
      totalCalories: items.fold(0, (s, i) => s + i.calories),
      items: items,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.7,
    );
  }

  /// If the AI omitted or zeroed out macros but reported valid calories,
  /// back-calculate macros from a standard ratio (15% P, 50% C, 35% F).
  /// Returns the original values when macros already look reasonable.
  (double?, double?, double?) _fillMacros(
    int calories,
    double? protein,
    double? carbs,
    double? fat,
  ) {
    if (calories <= 0) return (protein, carbs, fat);
    final macroKcal = (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9;
    if (macroKcal >= calories * 0.5) return (protein, carbs, fat);
    // Macros are missing or unrealistically small — estimate from calories.
    return (
      double.parse(((calories * 0.15) / 4).toStringAsFixed(1)),
      double.parse(((calories * 0.50) / 4).toStringAsFixed(1)),
      double.parse(((calories * 0.35) / 9).toStringAsFixed(1)),
    );
  }

  // ── Extract food items (Plan 022 §2.3) ────────────────────────────────────

  /// Single-inference structured extraction. Returns one [ExtractedFoodItem]
  /// per food the user mentioned, with a HyDE-style canonical description for
  /// downstream embedding search. Returns null when the model isn't loaded
  /// or output couldn't be parsed.
  ///
  /// Replaces the old normalize+macro-estimate two-call dance with one pass.
  @override
  Future<List<ExtractedFoodItem>?> extractFoodItems(String text) async {
    final model = _model;
    if (model == null) return null;

    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false,
      modelType: ModelType.qwen,
    );

    try {
      await chat.addQuery(
        Message(text: '$_extractFoodPrompt$text\nOutput:', isUser: true),
      );

      final response = await chat
          .generateChatResponse()
          .timeout(const Duration(seconds: 25));

      final raw =
          response is TextResponse ? response.token : response.toString();

      return _parseExtractResponse(raw, text);
    } catch (e) {
      debugPrint('OnDeviceAiCoachService.extractFoodItems failed: $e');
      return null;
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  /// Plan 027 §2.1 — on-device single-call parity (pick-only variant).
  /// Qwen extracts items AND attempts to pick a food_id from the candidate
  /// pool when one clearly matches. Unlike the cloud op, this does NOT
  /// estimate macros for unmatched items — the presenter falls through to
  /// the keyword bucket for those. Keeps Qwen on a task it can handle
  /// reliably (picking from a short list).
  @override
  Future<ParseFoodResult?> parseFoodWithCandidates(
    String text,
    List<FoodSearchCandidate> candidates,
  ) async {
    final model = _model;
    if (model == null) return null;

    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false,
      modelType: ModelType.qwen,
    );

    try {
      final candidatesBlock = candidates.isEmpty
          ? '(no candidates — set food_id to null for every item)'
          : candidates
              .take(10)
              .map((c) => '- id: ${c.entry.id}, name: ${c.entry.name}')
              .join('\n');

      final prompt =
          '$_parseFoodWithCandidatesPrompt\n\nCandidates:\n$candidatesBlock\n\n'
          'User: $text\nOutput:';
      await chat.addQuery(Message(text: prompt, isUser: true));

      final response = await chat
          .generateChatResponse()
          .timeout(const Duration(seconds: 25));

      final raw =
          response is TextResponse ? response.token : response.toString();

      return _parseExtractWithCandidatesResponse(raw, text, candidates);
    } catch (e) {
      debugPrint('OnDeviceAiCoachService.parseFoodWithCandidates failed: $e');
      return null;
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  /// Parses Qwen's JSON output for the candidate-picking variant. Validates
  /// every food_id against the actual candidate list — Qwen sometimes
  /// hallucinates ids that aren't in the input, which would resolve to the
  /// wrong food. Hallucinated ids are dropped to null so the caller falls
  /// through.
  ParseFoodResult? _parseExtractWithCandidatesResponse(
    String text,
    String original,
    List<FoodSearchCandidate> candidates,
  ) {
    // Try to find the wrapping object first (Plan 027 — {intent, items}).
    // Fall back to plain array if Qwen omitted the wrapper.
    String? intentStr;
    String? arrayJson;
    final objMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (objMatch != null) {
      try {
        final obj = jsonDecode(objMatch.group(0)!);
        if (obj is Map<String, dynamic>) {
          intentStr = obj['intent'] as String?;
          final items = obj['items'];
          if (items is List) arrayJson = jsonEncode(items);
        }
      } catch (_) {}
    }
    if (arrayJson == null) {
      final arrMatch = RegExp(r'\[[\s\S]*\]').firstMatch(text);
      if (arrMatch == null) return null;
      arrayJson = arrMatch.group(0);
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(arrayJson!);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;

    final validIds = {for (final c in candidates) c.entry.id};

    final out = <ExtractedFoodItem>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      final grams = (item['grams'] as num?)?.toDouble() ?? 100;
      final hyde = (item['hyde'] as String?)?.trim() ?? name;
      String? foodId = item['food_id'] as String?;
      if (foodId == 'null' || foodId == '') foodId = null;
      // Drop hallucinated ids — must appear in the candidate set we sent.
      if (foodId != null && !validIds.contains(foodId)) foodId = null;
      final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.0;
      out.add(ExtractedFoodItem(
        name: name,
        grams: grams,
        hydeDescription: hyde,
        rawText: name,
        resolvedFoodId: foodId,
        resolverConfidence: confidence,
      ));
    }
    if (out.isEmpty) return null;
    return ParseFoodResult(
      items: out,
      intent: ParseFoodResult.intentFromJson(intentStr),
    );
  }

  List<ExtractedFoodItem>? _parseExtractResponse(String text, String original) {
    final match = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (match == null) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(match.group(0)!);
    } catch (_) {
      return null;
    }

    final raw = decoded as List<dynamic>;
    var items = <ExtractedFoodItem>[];
    for (final r in raw) {
      final m = r as Map<String, dynamic>;
      final name = (m['name'] as String?)?.trim() ?? '';
      final grams = (m['grams'] as num?)?.toDouble() ?? 0.0;
      final hyde = (m['hyde'] as String?)?.trim() ?? '';
      if (name.isEmpty || grams <= 0) continue;
      items.add(ExtractedFoodItem(
        name: name,
        grams: grams,
        hydeDescription: hyde,
        rawText: original,
      ));
    }
    if (items.isEmpty) return null;

    // Canonical-USDA-name guard: short comma-separated noun phrases like
    // "Oats, Rolled, Dry" or "Beef, Ground, 80% Lean" are ONE ingredient.
    // The decompose prompt was over-eager and split them into 3+ items each.
    if (items.length > 1 && _looksLikeCanonicalUsdaName(original)) {
      final fallbackGrams =
          _singleItemExplicitGrams(original) ?? items.first.grams;
      return [
        ExtractedFoodItem(
          name: original.trim(),
          grams: fallbackGrams,
          hydeDescription: items.first.hydeDescription,
          rawText: original,
        ),
      ];
    }

    // Single-item gram reconciliation: when the user wrote one explicit gram
    // figure ("rolled oats 50g") and the LLM extracted exactly one item, trust
    // the user's number. The prompt examples nudge the model to canned values
    // ("1 cup rolled oats → 80g") and it sometimes re-anchors on those even
    // when the user provided an explicit weight.
    if (items.length == 1) {
      final userGrams = _singleItemExplicitGrams(original);
      if (userGrams != null && userGrams > 0) {
        final i = items.first;
        if ((i.grams - userGrams).abs() / userGrams > 0.05) {
          items = [
            ExtractedFoodItem(
              name: i.name,
              grams: userGrams,
              hydeDescription: i.hydeDescription,
              rawText: i.rawText,
            ),
          ];
        }
      }
    }

    // Safety net: if the user explicitly said "Xg total" / "Xg altogether" and
    // the model's per-item sum doesn't match, scale all items proportionally.
    // Only triggers on the explicit-total wording — implicit cases like
    // "150g pansit canton with pork" rely on the prompt examples to guide
    // the model, since detecting that pattern reliably from text is fragile.
    final stated = _explicitTotalGrams(original);
    if (stated != null && items.length > 1) {
      final sum = items.fold<double>(0, (s, i) => s + i.grams);
      // Only rescale when the model's drift is meaningful (>10% off).
      if (sum > 0 && (sum - stated).abs() / stated > 0.10) {
        final factor = stated / sum;
        return [
          for (final i in items)
            ExtractedFoodItem(
              name: i.name,
              grams: double.parse((i.grams * factor).toStringAsFixed(1)),
              hydeDescription: i.hydeDescription,
              rawText: i.rawText,
            ),
        ];
      }
    }
    return items;
  }

  /// Single explicit gram figure in the original text — used to override the
  /// model when the user gave a weight but the LLM hallucinated a different one.
  /// Returns null when zero or multiple gram figures appear (multi-item input).
  static double? _singleItemExplicitGrams(String text) {
    final matches = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:g|gm|gms|gram|grams)\b',
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.length != 1) return null;
    return double.tryParse(matches.first.group(1)!);
  }

  /// True when the input looks like one canonical USDA-style name made of
  /// comma-separated short modifiers — e.g. "Oats, Rolled, Dry" or "Beef,
  /// Ground, 80% Lean". Used to suppress the decompose-on-comma prompt rule
  /// for these single-ingredient inputs.
  static bool _looksLikeCanonicalUsdaName(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.length > 40) return false;
    if (lower.contains(' with ') ||
        lower.contains(' and ') ||
        lower.contains(' + ') ||
        lower.contains(' plus ')) {
      return false;
    }
    if (!lower.contains(',')) return false;
    final parts = lower.split(',').map((p) => p.trim()).toList();
    if (parts.length < 2) return false;
    // Each comma-separated part must be ONE short token (canonical descriptor).
    return parts.every((p) =>
        p.isNotEmpty &&
        !p.contains(' ') &&
        p.length <= 14 &&
        RegExp(r'^[a-z0-9%]+$').hasMatch(p));
  }

  /// Extracts an explicit total like "200g total" / "150 grams altogether".
  /// Returns null when the user didn't use a totalling keyword — implicit
  /// "150g [composite phrase]" is not matched here on purpose to avoid
  /// rescaling cases like "150g pork with rice" (single-ingredient weight).
  static double? _explicitTotalGrams(String text) {
    final m = RegExp(
      r'(\d+\.?\d*)\s*(?:g|gm|gms|gram|grams)\s*'
      r'(?:total|all in all|in total|altogether|all together)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  // ── Normalize food input ──────────────────────────────────────────────────

  @override
  Future<List<AiParsedFood>?> normalizeFoodInput(List<String> fragments) async {
    final model = _model;
    if (model == null || fragments.isEmpty) return null;

    final cacheKey = jsonEncode(fragments);
    final cached = _cacheGet(_normalizeCache, cacheKey);
    if (cached != null) return cached;

    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false,
      modelType: ModelType.qwen,
    );

    try {
      final inputJson = jsonEncode([
        for (var i = 0; i < fragments.length; i++) {'i': i, 't': fragments[i]},
      ]);
      await chat.addQuery(
        Message(text: '$_normalizePrompt$inputJson\nOutput:', isUser: true),
      );

      final response = await chat
          .generateChatResponse()
          .timeout(const Duration(seconds: 15));

      final text =
          response is TextResponse ? response.token : response.toString();

      final result = _parseNormalizeResponse(text, fragments.length);
      if (result != null) _cachePut(_normalizeCache, cacheKey, result);
      return result;
    } catch (e) {
      debugPrint('OnDeviceAiCoachService.normalizeFoodInput failed: $e');
      return null;
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  List<AiParsedFood>? _parseNormalizeResponse(String text, int expectedCount) {
    final match = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (match == null) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(match.group(0)!);
    } catch (_) {
      return null;
    }

    final rawItems = decoded as List<dynamic>;
    if (rawItems.length != expectedCount) return null;

    final items = List<AiParsedFood?>.filled(expectedCount, null);
    for (final raw in rawItems) {
      final map = raw as Map<String, dynamic>;
      final idx = (map['i'] as num?)?.toInt();
      // Strip commas and collapse whitespace so DB scoring isn't thrown off.
      final rawName = (map['n'] as String?)?.trim() ?? '';
      final name =
          rawName.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      final grams = (map['g'] as num?)?.toDouble();

      if (idx == null || idx < 0 || idx >= expectedCount) return null;
      if (name.isEmpty || grams == null || grams <= 0) return null;
      items[idx] = AiParsedFood(name: name, grams: grams);
    }

    if (items.any((i) => i == null)) return null;
    return items.cast<AiParsedFood>();
  }

  // ── Disambiguate food candidates ──────────────────────────────────────────

  @override
  Future<FoodDisambiguation?> disambiguateFood(
    String userQuery,
    List<FoodSearchCandidate> candidates,
  ) async {
    final model = _model;
    if (model == null || candidates.isEmpty) return null;

    // Number candidates 1..N for the prompt; keep ids on a parallel list.
    final ids = candidates.map((c) => c.entry.id).toList();
    final menu = StringBuffer();
    for (var i = 0; i < candidates.length; i++) {
      menu.writeln(
        '${i + 1}. ${candidates[i].entry.name}'
        '${candidates[i].entry.category != null ? ' [${candidates[i].entry.category}]' : ''}',
      );
    }

    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false,
      modelType: ModelType.qwen,
    );

    try {
      await chat.addQuery(
        Message(
          text: '$_disambiguatePrompt'
              'Query: "${userQuery.trim()}"\n'
              'Candidates:\n$menu'
              'Output:',
          isUser: true,
        ),
      );

      final response =
          await chat.generateChatResponse().timeout(const Duration(seconds: 5));

      final text =
          response is TextResponse ? response.token : response.toString();

      return _parseDisambiguateResponse(text, ids);
    } catch (e) {
      debugPrint('OnDeviceAiCoachService.disambiguateFood failed: $e');
      return null;
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  // ── Finance classifier step (Plan 026 §3.3) ───────────────────────────────

  static const _maxClarifyTurns = 3;

  @override
  Future<ClassifierStep?> runFinanceClassifierStep({
    required List<LedgerChatTurn> conversation,
    required PreparseResult preparse,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required int turnCount,
  }) async {
    // Hard turn budget — service won't burn more inference time once the user
    // has already been through the clarify loop the max number of times.
    if (turnCount >= _maxClarifyTurns) {
      return StepGiveUp(
        reason: 'Took too many tries — opening the form.',
        partialDraft: preparse.toDraft(),
      );
    }

    final model = _model;
    if (model == null) return null;

    final activeAccounts = accounts
        .where((a) => a.isActive && !a.isSubAccount && !a.isCustodian)
        .toList();

    final cacheKey = jsonEncode({
      'conv': conversation
          .map((t) => {'u': t.isUser, 't': t.text})
          .toList(growable: false),
      'acc': activeAccounts.map((a) => a.name).toList(growable: false),
      'cat': categories
          .map((c) => {'n': c.name, 't': c.type.name})
          .toList(growable: false),
      'dict': learnedMappings,
      'turn': turnCount,
    });
    final cached = _cacheGet(_financeClassifierCache, cacheKey);
    if (cached != null) return cached;

    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false,
      modelType: ModelType.qwen,
    );

    try {
      final prompt = _buildFinanceClassifierPrompt(
        conversation: conversation,
        preparse: preparse,
        categories: categories,
        accounts: activeAccounts,
        learnedMappings: learnedMappings,
      );
      await chat.addQuery(Message(text: prompt, isUser: true));

      final response =
          await chat.generateChatResponse().timeout(const Duration(seconds: 5));
      final text =
          response is TextResponse ? response.token : response.toString();

      final step = parseFinanceClassifierResponse(
        text: text,
        accounts: activeAccounts,
        categories: categories,
        preparse: preparse,
      );
      if (step != null) _cachePut(_financeClassifierCache, cacheKey, step);
      return step;
    } catch (e) {
      debugPrint('OnDeviceAiCoachService.runFinanceClassifierStep failed: $e');
      return null;
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  String _buildFinanceClassifierPrompt({
    required List<LedgerChatTurn> conversation,
    required PreparseResult preparse,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
  }) {
    final accountsJson =
        jsonEncode(accounts.map((a) => a.name).toList(growable: false));
    final categoriesJson = jsonEncode(categories
        .map((c) => {'name': c.name, 'type': c.type.name})
        .toList(growable: false));
    final dictJson = jsonEncode(learnedMappings);

    final transcript = StringBuffer();
    for (final t in conversation) {
      transcript.writeln(
        '  [${t.isUser ? 'user' : 'ai'}] "${t.text.replaceAll('"', "'")}"',
      );
    }

    final preparseSummary = jsonEncode({
      'amount': preparse.amount,
      'type': preparse.type?.name,
      'account': preparse.accountId == null
          ? null
          : _accountName(preparse.accountId!, accounts),
      'category': preparse.categoryId == null
          ? null
          : categories
              .firstWhere(
                (c) => c.id == preparse.categoryId,
                orElse: () => categories.first,
              )
              .name,
      'unresolved': preparse.unresolvedTokens,
      'ambiguous': preparse.ambiguousAccountTokens,
    });

    return 'You are a finance transaction assistant. Output JSON only.\n'
        '\n'
        'Existing accounts: $accountsJson\n'
        'Existing categories: $categoriesJson\n'
        'Learned token→category: $dictJson\n'
        '\n'
        'Conversation:\n$transcript\n'
        'Preparser knowledge: $preparseSummary\n'
        '\n'
        'Rules:\n'
        '- Pick accounts ONLY from the existing list. Never invent.\n'
        '- Pick categories ONLY from the existing list. Never invent.\n'
        '- If a token is unknown, infer or ask — don\'t guess silently.\n'
        '- If you have all required fields with confidence >= 0.8, return step:"resolved".\n'
        '- If unsure, return step:"clarify" with one question and optional quickReplies.\n'
        '- After $_maxClarifyTurns clarify turns total, return step:"give_up".\n'
        '\n'
        'Required fields:\n'
        '- inflow/outflow: amount, type, account, category, description\n'
        '- transfer:       amount, account, transferTo, description (no category)\n'
        '\n'
        'Output ONE of:\n'
        '  {"step":"resolved","amount":number,"type":"outflow|inflow|transfer",\n'
        '   "account":"<name>","transferTo":"<name>|null","category":"<name>|null",\n'
        '   "learnedToken":"<lowercase>|null","confidence":0.0-1.0,\n'
        '   "summaryText":"Log ₱500 outflow → Food (GCash)?"}\n'
        '  {"step":"clarify","question":"...",'
        '"quickReplies":[{"label":"...","replyText":"..."}]}\n'
        '  {"step":"give_up","reason":"..."}\n'
        'Output:';
  }

  String? _accountName(String id, List<FinancialAccount> accounts) {
    for (final a in accounts) {
      if (a.id == id) return a.name;
    }
    return null;
  }

  FoodDisambiguation? _parseDisambiguateResponse(
      String text, List<String> ids) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(match.group(0)!);
    } catch (_) {
      return null;
    }

    final json = decoded as Map<String, dynamic>;
    final pick = (json['pick'] as num?)?.toInt();
    final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    if (pick == null || pick < 1 || pick > ids.length) return null;

    return FoodDisambiguation(
      foodId: ids[pick - 1],
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  // ── Estimate macros per item ──────────────────────────────────────────────

  @override
  Future<List<AiItemEstimate>?> estimateMacrosForItems(
      List<AiParsedFood> items) async {
    final model = _model;
    if (model == null || items.isEmpty) return null;

    final cacheKey =
        jsonEncode(items.map((i) => {'n': i.name, 'g': i.grams}).toList());
    final cached = _cacheGet(_macroForItemsCache, cacheKey);
    if (cached != null) return cached;

    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false,
      modelType: ModelType.qwen,
    );

    try {
      final inputJson = jsonEncode([
        for (var i = 0; i < items.length; i++)
          {'i': i, 'n': items[i].name, 'g': items[i].grams.round()},
      ]);
      await chat.addQuery(
        Message(text: '$_itemMacrosPrompt$inputJson', isUser: true),
      );

      final response = await chat
          .generateChatResponse()
          .timeout(const Duration(seconds: 25));

      final text =
          response is TextResponse ? response.token : response.toString();

      final result = _parseItemMacrosResponse(text, items.length);
      if (result != null) _cachePut(_macroForItemsCache, cacheKey, result);
      return result;
    } catch (e) {
      debugPrint('OnDeviceAiCoachService.estimateMacrosForItems failed: $e');
      return null;
    } finally {
      try {
        await chat.session.close();
      } catch (_) {}
    }
  }

  List<AiItemEstimate>? _parseItemMacrosResponse(
      String text, int expectedCount) {
    final match = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (match == null) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(match.group(0)!);
    } catch (_) {
      return null;
    }

    final rawItems = decoded as List<dynamic>;
    if (rawItems.length != expectedCount) return null;

    final results = List<AiItemEstimate?>.filled(expectedCount, null);
    for (final raw in rawItems) {
      final map = raw as Map<String, dynamic>;
      final idx = (map['i'] as num?)?.toInt();
      if (idx == null || idx < 0 || idx >= expectedCount) return null;
      final calories = (map['calories'] as num?)?.toInt() ?? 0;
      if (calories <= 0) return null;
      final protein = (map['protein'] as num?)?.toDouble();
      final carbs = (map['carbs'] as num?)?.toDouble();
      final fat = (map['fat'] as num?)?.toDouble();
      final (ep, ec, ef) = _fillMacros(calories, protein, carbs, fat);
      results[idx] = AiItemEstimate(
        name: (map['name'] as String?) ?? '',
        calories: calories,
        protein: ep,
        carbs: ec,
        fat: ef,
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0.7,
      );
    }

    if (results.any((r) => r == null)) return null;
    return results.cast<AiItemEstimate>();
  }

  // ── Prompts ───────────────────────────────────────────────────────────────

  // Locale hint prepended to food prompts. Biases the model toward Filipino
  // dish recognition without changing Western food behavior.
  static const _localeHint = 'Cuisine context: Filipino + Western mix. '
      'Common Filipino dishes: adobo, sinigang, kare-kare, tocino, longganisa, pancit, tinola, bulalo.\n';

  // Single-pass food extraction prompt with HyDE-style canonical description.
  // Plan 022 §2.3 — Qwen3 0.6B handles this in one inference, replacing the
  // old normalize → DB lookup → AI macro estimate three-step dance.
  //
  // Decomposition rules (the "pansit canton with pork and cabbage" case):
  // when the user mixes a base dish with explicit add-ins/sides, output ONE
  // item per ingredient so each can be matched + scaled in the DB. When the
  // user names a single canonical dish ("chicken adobo", "sinigang"), keep
  // it as ONE item — the DB has those rows directly with accurate macros.
  // Plan 027 §2.1 — pick-only candidate-aware extraction. Same rules as
  // _extractFoodPrompt but each item gains a "food_id" + "confidence" pair,
  // plus a top-level "intent" classification for combine-vs-split logging.
  // No macro estimation here — keyword bucket handles unmatched items.
  static const _parseFoodWithCandidatesPrompt =
      'You are a food parser. Given user text and a list of candidate foods '
      'from the database, output ONLY a JSON object (no prose, no markdown):\n'
      '{"intent":"single_dish"|"items_list","items":[...]}\n\n'
      'Each item: {"name":"clean name","grams":number,"hyde":"USDA-style description",'
      '"food_id":"<id from candidates or null>","confidence":0.0-1.0}\n\n'
      'intent rules:\n'
      '- "single_dish": user is logging ONE composite dish (connectors like "with"/'
      '"at"/"into" with 2-4 ingredients, OR no per-item weights). Caller combines.\n'
      '- "items_list": user is logging SEPARATE items (per-item weights like '
      '"100g rice and 80g chicken", OR commas/"and" as list separators).\n\n'
      'Item rules:\n'
      '1. Convert units to grams (1 cup ≈ 240g, 1 tbsp = 15g, etc.).\n'
      '2. Decompose composite dishes when ingredients are listed; keep canonical '
      'dishes ("chicken adobo", "lechon kawali") as one item.\n'
      '3. For food_id: ONLY use ids from the Candidates list. No candidate fits → '
      'food_id=null, confidence=0.\n'
      '4. confidence: 0.0–0.5 weak, 0.6–0.8 decent, 0.9+ very confident.\n'
      '5. Default portion: 100g when unclear.\n'
      'Now process this input. ';

  static const _extractFoodPrompt =
      'You are a food parser for a calorie tracking app. Given user text, '
      'output ONLY a JSON array. No prose, no markdown.\n'
      'Each item: {"name":"clean food name","grams":number,"hyde":"USDA-style canonical description"}\n'
      'Rules:\n'
      '1. Convert units to grams. 1 cup ≈ 240g (rice/oats: 80g cooked weight = 1/3 cup dry). '
      '   1 scoop = 30g. 1 tbsp = 15g. 1 tsp = 5g. 1 piece varies by food.\n'
      '2. DECOMPOSE composite dishes when the user lists ingredients ("with", "and", '
      '   commas, multiple foods named). One JSON item per ingredient.\n'
      '   KEEP single canonical dishes as ONE item ("chicken adobo", "sinigang na baboy", '
      '   "kare-kare", "lechon kawali") — the DB has them with accurate macros.\n'
      '3. TOTAL-WEIGHT DISTRIBUTION: when the user gives ONE total weight for the whole '
      '   composite dish ("150g pansit canton with pork", "200g eggplant with sardines"), '
      '   distribute that total across the ingredients PROPORTIONALLY. The sum of "grams" '
      '   across items MUST equal the user-stated total.\n'
      '   Typical ratios when distributing a composite total:\n'
      '     stir-fry / pansit / fried-rice: starch 50%, protein 25%, veg 20%, oil+sauces 5%\n'
      '     soup / sinigang / nilaga / tinola: broth 40%, protein 20%, veg 35%, season 5%\n'
      '     ulam over rice (split rice from ulam if both stated): 50/50 unless user says\n'
      '4. For ingredients with NO total stated AND no per-ingredient grams, estimate Filipino '
      '   home-cooking portions:\n'
      '   • Main starch (rice, pansit, bihon, sotanghon): 150g cooked\n'
      '   • Protein (pork, chicken, beef, tofu, eggs): 80g cooked\n'
      '   • Vegetables (cabbage, sayote, kangkong, carrots, eggplant): 50g per veg\n'
      '   • Flavoring/canned (sardines as flavor, hotdog slices): 25g\n'
      '   • Cooking oil: 10g — INCLUDE for any sauteed/fried/stir-fried dish\n'
      '   • Soy sauce / patis: 10g if mentioned\n'
      '5. "name" is what the user said, lightly cleaned. "hyde" is the USDA canonical '
      '   description (preparation state included). Filipino dishes: keep local name + brief gloss.\n'
      '6. Fix obvious English typos in "name" (eg→egg, chiken→chicken, brocoli→broccoli, '
      '   yougurt→yogurt). Do NOT correct Filipino/Tagalog spelling — pansit/pancit, '
      '   adobong/adobo, lugaw/lugao are all valid; leave them as the user wrote them.\n'
      '7. Single canonical names with USDA-style commas like "Oats, Rolled, Dry" or '
      '   "Beef, Ground, 80% Lean" are ONE ingredient — DO NOT decompose them. '
      '   Output one item with the input as the name.\n'
      'Examples:\n'
      '"1 cup rolled oats" -> [{"name":"rolled oats","grams":80,"hyde":"Oats, rolled, regular and quick, dry, unenriched"}]\n'
      '"kefir milk" -> [{"name":"kefir","grams":240,"hyde":"Kefir, lowfat, plain"}]\n'
      '"1 scoop soy protein isolate" -> [{"name":"soy protein isolate","grams":30,"hyde":"Soy protein isolate, dry powder"}]\n'
      '"100g chicken adobo" -> [{"name":"chicken adobo","grams":100,"hyde":"Chicken adobo, Filipino braised chicken in soy sauce and vinegar"}]\n'
      '"pansit canton with pork and cabbage" -> ['
      '{"name":"pansit canton noodles","grams":150,"hyde":"Egg noodles, cooked"},'
      '{"name":"pork","grams":80,"hyde":"Pork, ground or sliced, cooked"},'
      '{"name":"cabbage","grams":50,"hyde":"Cabbage, raw shredded"},'
      '{"name":"carrots","grams":30,"hyde":"Carrots, raw"},'
      '{"name":"cooking oil","grams":10,"hyde":"Vegetable oil"},'
      '{"name":"soy sauce","grams":10,"hyde":"Soy sauce, made from soy and wheat"}]\n'
      // Total-weight distribution case — sums to user-stated 150g
      '"150g pansit canton with pork and cabbage" -> ['
      '{"name":"pansit canton noodles","grams":75,"hyde":"Egg noodles, cooked"},'
      '{"name":"pork","grams":38,"hyde":"Pork, ground or sliced, cooked"},'
      '{"name":"cabbage","grams":22,"hyde":"Cabbage, raw shredded"},'
      '{"name":"cooking oil","grams":8,"hyde":"Vegetable oil"},'
      '{"name":"soy sauce","grams":7,"hyde":"Soy sauce, made from soy and wheat"}]\n'
      // Soup distribution — 300g sinigang split per soup ratios
      '"300g sinigang na baboy with kangkong and gabi" -> ['
      '{"name":"sinigang broth","grams":120,"hyde":"Sinigang broth, sour soup base with tamarind"},'
      '{"name":"pork","grams":60,"hyde":"Pork, ribs or shoulder, cooked"},'
      '{"name":"kangkong","grams":55,"hyde":"Water spinach (kangkong), cooked"},'
      '{"name":"gabi","grams":50,"hyde":"Taro root (gabi), cooked"},'
      '{"name":"patis","grams":15,"hyde":"Fish sauce (patis)"}]\n'
      // Explicit "total" keyword — same distribution as implicit
      '"eggplant sauteed with sardine and tomato, 200g total" -> ['
      '{"name":"eggplant","grams":140,"hyde":"Eggplant, raw"},'
      '{"name":"sardines","grams":30,"hyde":"Sardines, canned in tomato sauce, drained"},'
      '{"name":"tomato","grams":20,"hyde":"Tomatoes, red, raw"},'
      '{"name":"cooking oil","grams":10,"hyde":"Vegetable oil"}]\n'
      // Per-ingredient grams stay as-stated, NOT redistributed
      '"150g pansit canton, 80g pork, 50g cabbage" -> ['
      '{"name":"pansit canton noodles","grams":150,"hyde":"Egg noodles, cooked"},'
      '{"name":"pork","grams":80,"hyde":"Pork, ground or sliced, cooked"},'
      '{"name":"cabbage","grams":50,"hyde":"Cabbage, raw shredded"},'
      '{"name":"cooking oil","grams":10,"hyde":"Vegetable oil"}]\n'
      '"sardine pansit bihon" -> ['
      '{"name":"pansit bihon","grams":150,"hyde":"Rice noodles, cooked"},'
      '{"name":"sardines","grams":30,"hyde":"Sardines, canned in tomato sauce, drained"},'
      '{"name":"cooking oil","grams":10,"hyde":"Vegetable oil"}]\n'
      '"eggplant sauteed with sardines and tomato" -> ['
      '{"name":"eggplant","grams":150,"hyde":"Eggplant, raw"},'
      '{"name":"sardines","grams":25,"hyde":"Sardines, canned in tomato sauce, drained"},'
      '{"name":"tomato","grams":40,"hyde":"Tomatoes, red, raw"},'
      '{"name":"cooking oil","grams":10,"hyde":"Vegetable oil"}]\n'
      '"rice and adobo" -> ['
      '{"name":"white rice","grams":150,"hyde":"Rice, white, long-grain, regular, cooked"},'
      '{"name":"chicken adobo","grams":100,"hyde":"Chicken adobo, Filipino braised chicken in soy sauce and vinegar"}]\n'
      '"sinigang na baboy" -> [{"name":"sinigang na baboy","grams":300,"hyde":"Sinigang, Filipino sour pork soup with vegetables and tamarind broth"}]\n'
      '$_localeHint'
      'User: ';

  static const _normalizePrompt =
      'You are a food normalizer. Given a JSON array of {"i":index,"t":"raw food text"}, '
      'output a JSON array of {"i":index,"n":"clean food name","g":gram_weight}.\n'
      'Same indices, same order. Convert any volume/unit to grams using food-specific density.\n'
      'Rules:\n'
      '1. Strip brand names — keep only the short generic food name (2-4 words max). '
      '   e.g. "birchtree powdered milk" → "skim milk powder", "nestle milo" → "milo powder"\n'
      '2. Do NOT add any preparation method not stated in the input. '
      '   "potato" → "potato", NOT "potato chips" or "potato fries"\n'
      '3. Preserve explicitly stated preparation: '
      '   "fried potato" → "fried potato", "potato chips" → "potato chips"\n'
      '4. Keep Filipino dish names as-is: "chicken adobo" → "chicken adobo"\n'
      'No explanation, no markdown.\n'
      '$_localeHint'
      'Examples:\n'
      '[{"i":0,"t":"100gms skim milk"}] → [{"i":0,"n":"skim milk","g":100}]\n'
      '[{"i":0,"t":"3 cups cooked rice"},{"i":1,"t":"1 tbspoon olive oil"}] → '
      '[{"i":0,"n":"white rice cooked","g":555},{"i":1,"n":"olive oil","g":14}]\n'
      '[{"i":0,"t":"42g potato"}] → [{"i":0,"n":"potato","g":42}]\n'
      '[{"i":0,"t":"200g chicken adobo"}] → [{"i":0,"n":"chicken adobo","g":200}]\n'
      'Input: ';

  static const _macroEstimatePrompt = 'You are a nutrition database API. '
      'Given a meal description, respond with ONLY a valid JSON object — '
      'no preamble, no markdown fences, no explanation.\n'
      'Required format:\n'
      '{"items":[{"name":"string","calories":integer,'
      '"protein":number,"carbs":number,"fat":number}],'
      '"confidence":number}\n\n'
      'Meal: ';

  static const _itemMacrosPrompt =
      'You are a nutrition API. Given indexed food items with exact gram weights, '
      'return macros computed for those exact grams.\n'
      'Input: JSON array [{i,n,g}] — i=index, n=name, g=grams\n'
      'Output ONLY a JSON array (no markdown, no explanation):\n'
      '[{"i":index,"name":"name","calories":integer,'
      '"protein":number,"carbs":number,"fat":number,"confidence":number}]\n'
      'Same indices. calories/protein/carbs/fat are for the exact g given. '
      'confidence is 0.0–1.0 based on how certain you are.\n'
      'Example:\n'
      'Input: [{"i":0,"n":"chicken breast","g":200}]\n'
      'Output: [{"i":0,"name":"chicken breast","calories":330,"protein":62,"carbs":0,"fat":7,"confidence":0.9}]\n'
      '$_localeHint'
      'Input: ';

  static const _disambiguatePrompt =
      'You are a food matcher. Given a user query and a numbered list of '
      'candidate foods, pick the candidate that best matches the query.\n'
      'Output ONLY a JSON object: {"pick": integer_1_to_N, "confidence": 0.0_to_1.0}\n'
      'Confidence reflects how certain you are. Lower it when multiple candidates fit. '
      'Use the candidate category as a tiebreaker.\n'
      'No markdown, no explanation.\n'
      '$_localeHint'
      'Examples:\n'
      'Query: "creamy yogurt with berries"\n'
      'Candidates:\n1. Yogurt, plain, whole milk [Dairy]\n'
      '2. Berries, mixed, frozen [Fruit]\n3. Yogurt, vanilla, low fat [Dairy]\n'
      'Output: {"pick":1,"confidence":0.85}\n\n';

  static const _foodParsePrompt =
      'You are a food parser. Extract food items from the input.\n'
      'Respond with ONLY a JSON array. No explanation, no markdown.\n'
      'Format: [{"name":"food name","quantity":number,"unit":"unit or null","grams":number_or_null}]\n'
      'If you know the gram weight directly, set "grams". Otherwise set "quantity" + "unit".\n'
      'Examples:\n'
      '  "2 cups rice" → [{"name":"rice","quantity":2,"unit":"cup","grams":null}]\n'
      '  "150g chicken breast" → [{"name":"chicken breast","quantity":150,"unit":"g","grams":150}]\n'
      '  "2 medium eggs" → [{"name":"egg","quantity":2,"unit":"piece","grams":100}]\n'
      '  "30grams of whole wheat bread" → [{"name":"whole wheat bread","quantity":30,"unit":"g","grams":30}]\n'
      'Input: ';

  static const Map<AiCoachEntryPoint, String> _personas = {
    AiCoachEntryPoint.nutrition:
        'You are a nutrition coach inside a gamified fasting app called The System. '
            'Help the user log food accurately, hit their macro goals, and optimize their eating window.',
    AiCoachEntryPoint.fasting: 'You are a fasting coach inside The System. '
        'Guide the player through their fast, explain phases (ketosis, autophagy), and keep them motivated.',
    AiCoachEntryPoint.stats:
        'You are the Shadow Monarch — the RPG advisor of The System. '
            'Analyze the player\'s XP, level, HP, and streaks. Give strategic advice to level up faster.',
    AiCoachEntryPoint.treasury: 'You are a finance analyst inside The System. '
        'Review the player\'s budget, spending, and savings. Give concise, actionable insights.',
    AiCoachEntryPoint.general:
        'You are The System\'s AI Coach — a health and wellness advisor with an RPG twist. '
            'You cover fasting, nutrition, fitness, and personal finance. Be direct and motivating.',
  };
}
