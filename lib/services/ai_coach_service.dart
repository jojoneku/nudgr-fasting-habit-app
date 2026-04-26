import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
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
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
  });

  /// Attempt to parse [description] as a food log entry.
  ///
  /// Returns null if the text is clearly not a food description.
  /// Implementations may use the model or fall back to rule-based logic.
  Future<FoodParseResult?> parseFood(String description);

  void dispose();
}
