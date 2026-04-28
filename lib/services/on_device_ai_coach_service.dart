import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/ai_meal_estimate.dart';
import '../models/ai_parsed_food.dart';
import '../models/food_parse_result.dart';
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

  InferenceModel? _model;
  bool _isDownloading = false;
  int _downloadProgress = 0;
  bool _deviceIncompatible = false;

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
      await FlutterGemma.initialize();

      if (FlutterGemma.hasActiveModel()) {
        await _loadModel();
        return;
      }

      await FlutterGemma.installModel(
        modelType: ModelType.qwen,
        fileType: ModelFileType.task,
      )
          .fromNetwork(_modelUrl)
          .withProgress((p) {
            _downloadProgress = p;
            onProgress?.call(p);
          })
          .install();

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
          debugPrint(
              'OnDeviceAiCoachService: device incompatible — $cpuError');
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
          final text = systemPrepended
              ? msg.text
              : '$systemContext\n\n${msg.text}';
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

      final text = response is TextResponse
          ? response.token
          : response.toString();

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
            final before = text.substring(0, start).replaceAll(specialTokenRe, '');
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
    final persona = _personas[context.entryPoint] ?? _personas[AiCoachEntryPoint.general]!;
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
        resolvedGrams = FoodUnitConverter.convert(qty, unit, foodName: name) ?? 100.0;
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

      final text = response is TextResponse
          ? response.token
          : response.toString();

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
      return AiItemEstimate(
        name: (item['name'] as String?) ?? description,
        calories: (item['calories'] as num?)?.toInt() ?? 0,
        protein: (item['protein'] as num?)?.toDouble(),
        carbs: (item['carbs'] as num?)?.toDouble(),
        fat: (item['fat'] as num?)?.toDouble(),
      );
    }).toList();

    if (items.isEmpty) return null;
    return AiMealEstimate(
      totalCalories: items.fold(0, (s, i) => s + i.calories),
      items: items,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.7,
    );
  }

  // ── Normalize food input ──────────────────────────────────────────────────

  @override
  Future<List<AiParsedFood>?> normalizeFoodInput(
      List<String> fragments) async {
    final model = _model;
    if (model == null || fragments.isEmpty) return null;

    final chat = await model.createChat(
      temperature: 0.1,
      topK: 1,
      isThinking: false,
      modelType: ModelType.qwen,
    );

    try {
      // Indexed input so we can detect ordering/alignment issues in the output.
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

      return _parseNormalizeResponse(text, fragments.length);
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

  // ── Prompts ───────────────────────────────────────────────────────────────

  static const _normalizePrompt =
      'You are a food normalizer. Given a JSON array of {"i":index,"t":"raw food text"}, '
      'output a JSON array of {"i":index,"n":"clean food name","g":gram_weight}.\n'
      'Same indices, same order. Convert any volume/unit to grams using food-specific density.\n'
      'Rules:\n'
      '1. Strip brand names — output only the generic food name. '
      '   e.g. "birchtree powdered milk" → "powdered whole milk", "nestle milo" → "milo chocolate drink"\n'
      '2. Do NOT add any preparation method not stated in the input. '
      '   "potato" → "potato", NOT "potato chips" or "potato fries"\n'
      '3. Preserve explicitly stated preparation: '
      '   "fried potato" → "fried potato", "potato chips" → "potato chips"\n'
      'No explanation, no markdown.\n'
      'Examples:\n'
      '[{"i":0,"t":"100gms skim milk"}] → [{"i":0,"n":"skim milk","g":100}]\n'
      '[{"i":0,"t":"3 cups cooked rice"},{"i":1,"t":"1 tbspoon olive oil"}] → '
      '[{"i":0,"n":"white rice cooked","g":555},{"i":1,"n":"olive oil","g":14}]\n'
      '[{"i":0,"t":"42g potato"}] → [{"i":0,"n":"potato","g":42}]\n'
      '[{"i":0,"t":"birchtree powdered milk 33g"}] → [{"i":0,"n":"powdered whole milk","g":33}]\n'
      'Input: ';

  static const _macroEstimatePrompt =
      'You are a nutrition database API. '
      'Given a meal description, respond with ONLY a valid JSON object — '
      'no preamble, no markdown fences, no explanation.\n'
      'Required format:\n'
      '{"items":[{"name":"string","calories":integer,'
      '"protein":number,"carbs":number,"fat":number}],'
      '"confidence":number}\n\n'
      'Meal: ';

  static const _foodParsePrompt =
      'You are a food parser. Extract food items from the input.\n'
      'Respond with ONLY a JSON array. No explanation, no markdown.\n'
      'Format: [{"name":"food name","quantity":number,"unit":"unit or null","grams":number_or_null}]\n'
      'If you know the gram weight directly, set "grams". Otherwise set "quantity" + "unit".\n'
      'Examples:\n'
      '  "2 cups rice" → [{"name":"rice","quantity":2,"unit":"cup","grams":null}]\n'
      '  "150g chicken breast" → [{"name":"chicken breast","quantity":150,"unit":"g","grams":150}]\n'
      '  "2 medium eggs" → [{"name":"egg","quantity":2,"unit":"piece","grams":120}]\n'
      '  "30grams of whole wheat bread" → [{"name":"whole wheat bread","quantity":30,"unit":"g","grams":30}]\n'
      'Input: ';

  static const Map<AiCoachEntryPoint, String> _personas = {
    AiCoachEntryPoint.nutrition:
        'You are a nutrition coach inside a gamified fasting app called The System. '
        'Help the user log food accurately, hit their macro goals, and optimize their eating window.',
    AiCoachEntryPoint.fasting:
        'You are a fasting coach inside The System. '
        'Guide the player through their fast, explain phases (ketosis, autophagy), and keep them motivated.',
    AiCoachEntryPoint.stats:
        'You are the Shadow Monarch — the RPG advisor of The System. '
        'Analyze the player\'s XP, level, HP, and streaks. Give strategic advice to level up faster.',
    AiCoachEntryPoint.treasury:
        'You are a finance analyst inside The System. '
        'Review the player\'s budget, spending, and savings. Give concise, actionable insights.',
    AiCoachEntryPoint.general:
        'You are The System\'s AI Coach — a health and wellness advisor with an RPG twist. '
        'You cover fasting, nutrition, fitness, and personal finance. Be direct and motivating.',
  };
}
