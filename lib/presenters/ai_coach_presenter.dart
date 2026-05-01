import 'package:flutter/material.dart';

import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/food_db_entry.dart';
import '../models/food_parse_result.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../services/ai_coach_service.dart';
import '../services/null_ai_coach_service.dart';
import '../services/on_device_ai_coach_service.dart';

const int _maxHistoryMessages = 50;

class AiCoachPresenter extends ChangeNotifier {
  final StatsPresenter _stats;
  final FastingPresenter _fasting;
  final NutritionPresenter? _nutrition;

  AiCoachService _service;
  AiCoachTier _activeTier = AiCoachTier.onDevice;

  AiCoachEntryPoint _entryPoint = AiCoachEntryPoint.general;
  final List<AiChatMessage> _messages = [];
  bool _isResponding = false;
  bool _isThinkingEnabled = false;
  bool _isInitializing = true;
  String? _errorMessage;

  AiCoachPresenter({
    required StatsPresenter stats,
    required FastingPresenter fasting,
    NutritionPresenter? nutrition,
    AiCoachService? service,
  })  : _stats = stats,
        _fasting = fasting,
        _nutrition = nutrition,
        _service = service ?? NullAiCoachService() {
    // If a real service was injected (already initialised externally), skip
    // the internal init. Only auto-init when no service is provided.
    if (service == null) {
      _initOnDevice();
    } else {
      _isInitializing = false;
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  bool get isResponding => _isResponding;
  bool get isModelAvailable => _service.isAvailable;
  int? get downloadProgress => _service.downloadProgress;
  bool get isDownloading => downloadProgress != null;
  bool get isInitializing => _isInitializing;
  AiCoachTier get activeTier => _activeTier;
  AiCoachEntryPoint get entryPoint => _entryPoint;
  String? get errorMessage => _errorMessage;
  bool get isThinkingEnabled => _isThinkingEnabled;

  // ── Session ───────────────────────────────────────────────────────────────

  /// Open a new chat session scoped to [entryPoint].
  void openSession(AiCoachEntryPoint entryPoint) {
    _entryPoint = entryPoint;
    _messages.clear();
    _errorMessage = null;
    notifyListeners();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> send(String text) async {
    if (text.trim().isEmpty || _isResponding) return;

    final userMsg = AiChatMessage.user(text.trim());
    _messages.add(userMsg);
    _errorMessage = null;
    _isResponding = true;
    notifyListeners();

    // Add streaming placeholder for assistant.
    final assistantMsg = AiChatMessage.assistantStreaming();
    _messages.add(assistantMsg);
    notifyListeners();

    try {
      final context = _buildContext();
      final buffer = StringBuffer();

      await for (final token in _service.respond(
        messages: _userVisibleMessages(),
        context: context,
        isThinking: _isThinkingEnabled,
      )) {
        buffer.write(token);
        _updateLastMessage(buffer.toString(), isStreaming: true);
        notifyListeners();
      }

      _updateLastMessage(buffer.toString(), isStreaming: false);
    } catch (e) {
      _errorMessage = 'Something went wrong. Try again.';
      _updateLastMessage('', isStreaming: false);
      debugPrint('AiCoachPresenter.send error: $e');
    } finally {
      _isResponding = false;
      _trimHistory();
      notifyListeners();
    }
  }

  // ── Food parse ────────────────────────────────────────────────────────────

  /// Parse a food description and return matched DB entries for confirmation.
  /// Sends a chat message showing what was found.
  Future<List<(ParsedFoodItem, FoodDbEntry?)>> parseAndPreview(
    String description,
  ) async {
    final result = await _service.parseFood(description);
    if (result == null || result.isEmpty) return [];

    final nutrition = _nutrition;
    if (nutrition == null) return [];

    await nutrition.parseMeal(description);
    final matches = nutrition.parsedDbMatches;

    return List.generate(
      result.items.length,
      (i) => (result.items[i], i < matches.length ? matches[i] : null),
    );
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> downloadModel() async {
    if (_service is! OnDeviceAiCoachService) {
      _service = OnDeviceAiCoachService();
    }
    notifyListeners();
    try {
      await _service.downloadModel(onProgress: (_) => notifyListeners());
    } catch (e) {
      _errorMessage = 'Download failed. Check your connection and try again.';
      debugPrint('AiCoachPresenter.downloadModel error: $e');
    }
    notifyListeners();
  }

  // ── Tier ─────────────────────────────────────────────────────────────────

  void setTier(AiCoachTier tier) {
    if (_activeTier == tier) return;
    _activeTier = tier;
    notifyListeners();
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  void clearHistory() {
    _messages.clear();
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void toggleThinking() {
    _isThinkingEnabled = !_isThinkingEnabled;
    notifyListeners();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _initOnDevice() async {
    final svc = OnDeviceAiCoachService();
    await svc.init();
    _service = svc;
    _isInitializing = false;
    notifyListeners();
  }

  AiCoachContext _buildContext() {
    final stats = _stats.stats;
    final n = _nutrition;

    return AiCoachContext(
      entryPoint: _entryPoint,
      isFasting: _fasting.isFasting,
      elapsedFastMinutes:
          _fasting.isFasting ? _fasting.elapsedSeconds ~/ 60 : null,
      fastingGoalHours: _fasting.fastingGoalHours,
      fastingStreak: stats.streak,
      playerLevel: stats.level,
      playerXp: stats.currentXp,
      playerHp: stats.currentHp,
      todayCalories: n?.todayCalories,
      calorieGoal: n?.effectiveGoal,
      todayProtein: n?.todayProtein,
      todayCarbs: n?.todayCarbs,
      todayFat: n?.todayFat,
    );
  }

  List<AiChatMessage> _userVisibleMessages() =>
      _messages.where((m) => !m.isStreaming && m.text.isNotEmpty).toList();

  void _updateLastMessage(String text, {required bool isStreaming}) {
    if (_messages.isEmpty) return;
    _messages[_messages.length - 1] =
        _messages.last.copyWith(text: text, isStreaming: isStreaming);
  }

  void _trimHistory() {
    if (_messages.length > _maxHistoryMessages) {
      _messages.removeRange(0, _messages.length - _maxHistoryMessages);
    }
  }
}
