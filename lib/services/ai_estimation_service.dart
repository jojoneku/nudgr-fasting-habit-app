import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/ai_meal_estimate.dart';

/// On-device meal calorie estimation via flutter_gemma (Gemma 3 270M IT Q8).
///
/// The model is downloaded once to the flutter_gemma managed store (~450 MB).
/// Inference runs fully on-device — no internet required after download.
///
/// Lifecycle:
///   1. Call [init] at app startup (non-blocking — loads model if already installed).
///   2. User triggers [downloadModel] to download on first use.
///   3. Call [estimate] to get structured calorie breakdown.
class AiEstimationService {
  // Gemma 3 1B IT Q8 — litert-community gated repo, ~700 MB.
  // Requires a HuggingFace account with access granted at:
  // https://huggingface.co/litert-community/Gemma3-1B-IT
  static const _modelUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task';
  static const _modelSizeLabel = '~700 MB';

  /// HuggingFace read token — required to download the gated model.
  /// Generate one at https://huggingface.co/settings/tokens
  final String? huggingFaceToken;

  AiEstimationService({this.huggingFaceToken});

  // System prompt that constrains the model to JSON-only output.
  static const _systemPrompt =
      'You are a nutrition database API. '
      'Given a meal description, respond with ONLY a valid JSON object — '
      'no preamble, no markdown fences, no explanation.\n'
      'Required format:\n'
      '{"items":[{"name":"string","calories":integer,'
      '"protein":number,"carbs":number,"fat":number}],'
      '"confidence":number}\n\n'
      'Meal: ';

  InferenceModel? _model;
  bool _isDownloading = false;
  int _downloadProgress = 0; // 0–100

  // ── State getters ────────────────────────────────────────────────────────────

  bool get isModelAvailable  => _model != null;
  bool get isDownloading     => _isDownloading;
  int  get downloadProgress  => _downloadProgress;
  String get modelSizeLabel  => _modelSizeLabel;

  // ── Init ─────────────────────────────────────────────────────────────────────

  /// Call once at app startup. Loads an already-installed model silently.
  Future<void> init() async {
    await FlutterGemma.initialize(huggingFaceToken: huggingFaceToken);
    if (!FlutterGemma.hasActiveModel()) return;
    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.gpu,
      );
    } catch (_) {
      // GPU not available — fall back to CPU.
      try {
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 512,
          preferredBackend: PreferredBackend.cpu,
        );
      } catch (_) {
        // Model load failed; isModelAvailable stays false.
      }
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────────

  /// Downloads and installs the model. Reports 0–100 progress via [onProgress].
  /// Safe to call multiple times; no-ops if already downloading.
  Future<void> downloadModel({void Function(int progress)? onProgress}) async {
    if (_isDownloading) return;
    _isDownloading   = true;
    _downloadProgress = 0;

    try {
      await FlutterGemma.initialize(huggingFaceToken: huggingFaceToken);
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(_modelUrl)
          .withProgress((p) {
            _downloadProgress = p;
            onProgress?.call(p);
          })
          .install();

      // Load the model after successful installation.
      try {
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 512,
          preferredBackend: PreferredBackend.gpu,
        );
      } catch (_) {
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 512,
          preferredBackend: PreferredBackend.cpu,
        );
      }
    } finally {
      _isDownloading = false;
    }
  }

  // ── Estimate ─────────────────────────────────────────────────────────────────

  /// Returns a structured calorie breakdown for [description].
  /// Throws [UnsupportedError] if the model is not loaded.
  /// Throws [FormatException] if the model output cannot be parsed.
  Future<AiMealEstimate> estimate(String description) async {
    final model = _model;
    if (model == null) throw UnsupportedError('AI model not loaded.');

    // Create a fresh single-use chat session for each inference.
    final chat = await model.createChat(
      temperature: 0.3, // Lower = more deterministic JSON output.
      topK: 1,
      modelType: ModelType.gemmaIt,
    );

    await chat.addQuery(
      Message(text: '$_systemPrompt$description', isUser: true),
    );

    ModelResponse response;
    try {
      response = await chat.generateChatResponse();
    } finally {
      // Always release the native session to avoid memory accumulation.
      await chat.session.close();
    }

    return _parseResponse(response, description);
  }

  // ── Parsing ───────────────────────────────────────────────────────────────────

  AiMealEstimate _parseResponse(ModelResponse response, String description) {
    if (response is FunctionCallResponse) {
      // Shouldn't happen with gemmaIt, but handle gracefully.
      return AiMealEstimate(
        totalCalories: 0,
        items: [AiItemEstimate(name: description, calories: 0)],
        confidence: 0.5,
      );
    }

    final text =
        response is TextResponse ? response.token : response.toString();

    // Extract the first JSON object from the response text.
    // The model may occasionally prepend a short explanation.
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) {
      throw FormatException('No JSON object found in AI response: $text');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(match.group(0)!);
    } catch (e) {
      throw FormatException('Failed to decode AI response JSON: $e');
    }

    final json     = decoded as Map<String, dynamic>;
    final rawItems = json['items'] as List<dynamic>? ?? [];

    final items = rawItems.map((raw) {
      final item = raw as Map<String, dynamic>;
      return AiItemEstimate(
        name:     (item['name']     as String?) ?? 'Unknown',
        calories: (item['calories'] as num?)?.toInt() ?? 0,
        protein:  (item['protein']  as num?)?.toDouble(),
        carbs:    (item['carbs']    as num?)?.toDouble(),
        fat:      (item['fat']      as num?)?.toDouble(),
      );
    }).toList();

    return AiMealEstimate(
      totalCalories: items.fold(0, (sum, i) => sum + i.calories),
      items:         items,
      confidence:    (json['confidence'] as num?)?.toDouble() ?? 0.7,
    );
  }
}
