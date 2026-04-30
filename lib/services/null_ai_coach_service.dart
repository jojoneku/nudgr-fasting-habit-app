import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/ai_meal_estimate.dart';
import '../models/ai_parsed_food.dart';
import '../models/food_parse_result.dart';
import 'ai_coach_service.dart';

/// Stub implementation used before the on-device model is downloaded or
/// when no network is available for the cloud tier.
class NullAiCoachService implements AiCoachService {
  @override
  bool get isAvailable => false;

  @override
  int? get downloadProgress => null;

  @override
  AiCoachTier get tier => AiCoachTier.onDevice;

  @override
  Future<void> downloadModel({void Function(int progress)? onProgress}) async {}

  @override
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  }) async* {
    yield _cannedResponse(context);
  }

  @override
  Future<FoodParseResult?> parseFood(String description) async => null;

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

  @override
  void dispose() {}

  String _cannedResponse(AiCoachContext context) {
    return switch (context.entryPoint) {
      AiCoachEntryPoint.nutrition =>
        'Download the AI Coach to get smart food logging — '
            'I\'ll read from your food database for accurate macros.',
      AiCoachEntryPoint.fasting =>
        'Download the AI Coach to unlock fasting insights and phase guidance.',
      AiCoachEntryPoint.stats =>
        'Download the AI Coach to get RPG strategy tips and XP maximisation advice.',
      AiCoachEntryPoint.treasury =>
        'Download the AI Coach to get personalised finance analysis.',
      AiCoachEntryPoint.general =>
        'The AI Coach isn\'t downloaded yet. '
            'Tap "Download AI Coach" to unlock on-device intelligence (~586 MB).',
    };
  }
}
