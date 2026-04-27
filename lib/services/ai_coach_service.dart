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
  ///
  /// [messages] is the conversation history (oldest first).
  /// [context] is the current app state snapshot.
  /// [isThinking] enables extended reasoning (slower but deeper).
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  });

  /// Attempt to parse [description] as a food log entry.
  ///
  /// Returns null if the text is clearly not a food description.
  /// Implementations may use the model or fall back to rule-based logic.
  Future<FoodParseResult?> parseFood(String description);

  /// Estimate calories and macros for a natural-language food description.
  ///
  /// Returns null if the model is unavailable or inference fails.
  Future<AiMealEstimate?> estimateMacros(String description);

  /// Normalize raw food fragments into clean names and gram weights.
  ///
  /// Each fragment is a single food item as typed by the user (e.g.
  /// "100gms skim milk", "3 cups rice"). The returned list has the same
  /// length and order as [fragments]. Returns null if AI is unavailable or
  /// the response cannot be reliably aligned.
  Future<List<AiParsedFood>?> normalizeFoodInput(List<String> fragments);

  void dispose();
}
