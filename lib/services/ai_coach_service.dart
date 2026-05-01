import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/ai_meal_estimate.dart';
import '../models/ai_parsed_food.dart';
import '../models/food_parse_result.dart';

/// Tier of the active AI Coach service.
enum AiCoachTier { onDevice, cloud }

/// Abstract interface for all AI Coach implementations.
///
/// Implementations:
///   - [NullAiCoachService]      — canned responses (before model download)
///   - [OnDeviceAiCoachService]  — Qwen3 0.6B via flutter_gemma
///   - [CloudAiCoachService]     — AWS Lambda → Amazon Bedrock Claude Haiku
abstract class AiCoachService {
  /// Whether this service is ready to respond.
  bool get isAvailable;

  /// Download progress 0–100. Null if not downloading or not applicable.
  int? get downloadProgress;

  /// Tier this service belongs to.
  AiCoachTier get tier;

  /// Download / initialise the underlying model.
  /// No-op for cloud implementations.
  Future<void> downloadModel({void Function(int progress)? onProgress});

  /// Stream a response token-by-token.
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  });

  /// Attempt to parse [description] as a food log entry.
  Future<FoodParseResult?> parseFood(String description);

  /// Estimate calories and macros for a natural-language food description.
  /// Used for the standalone estimation UI (estimateMeal flow).
  Future<AiMealEstimate?> estimateMacros(String description);

  /// Estimate macros for a list of food items with known gram weights.
  ///
  /// Each item is `{name, grams}`. Returns one [AiItemEstimate] per input item
  /// in the same order, with calories already computed for the exact grams.
  /// Returns null if the model is unavailable, inference fails, or the response
  /// length doesn't match the input.
  Future<List<AiItemEstimate>?> estimateMacrosForItems(
    List<AiParsedFood> items,
  );

  /// Normalize raw food fragments into clean names and gram weights.
  Future<List<AiParsedFood>?> normalizeFoodInput(List<String> fragments);

  void dispose();
}
