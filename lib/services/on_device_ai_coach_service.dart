import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
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

  @override
  AiCoachTier get tier => AiCoachTier.onDevice;

  @override
  bool get isAvailable => _model != null;

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
    } catch (_) {
      try {
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 4096,
          preferredBackend: PreferredBackend.cpu,
        );
      } catch (e) {
        debugPrint('OnDeviceAiCoachService: model load failed: $e');
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
  }) async* {
    final model = _model;
    if (model == null) {
      yield _unavailableMessage(context);
      return;
    }

    final chat = await model.createChat(
      temperature: 0.7,
      topK: 40,
      isThinking: true,
      modelType: ModelType.qwen,
    );

    try {
      // Inject context as the first user message (system instruction pattern).
      final systemTurn = _buildSystemTurn(context);
      await chat.addQuery(Message(text: systemTurn, isUser: true));

      // Replay conversation history (skip first user message — already added).
      for (final msg in messages.skip(messages.length > 1 ? 1 : 0)) {
        if (msg.role == AiChatRole.user) {
          await chat.addQuery(Message(text: msg.text, isUser: true));
        }
        // Assistant turns are part of the session context automatically.
      }

      // Stream the response.
      final response = await chat.generateChatResponse().timeout(
            const Duration(seconds: 90),
          );

      final text = response is TextResponse
          ? response.token
          : response.toString();

      // Strip <think>...</think> blocks — Qwen3 thinking tokens aren't
      // meant to be shown to the user.
      yield _stripThinking(text);
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

  bool _allItemsHaveExactUnits(FoodParseResult result) =>
      result.items.every((i) => !i.isEstimated);

  String _buildSystemTurn(AiCoachContext context) {
    final persona = _personas[context.entryPoint] ?? _personas[AiCoachEntryPoint.general]!;
    return '$persona\n\n${context.toPromptSummary()}\n\nRespond concisely. '
        'Do not repeat the stats back. Be direct and helpful.';
  }

  String _stripThinking(String text) {
    return text
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .trim();
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

  // ── Prompts ───────────────────────────────────────────────────────────────

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
