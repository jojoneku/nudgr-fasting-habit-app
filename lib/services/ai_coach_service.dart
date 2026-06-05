import 'dart:typed_data';

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

  /// Single-pass extraction with HyDE descriptions for hybrid search
  /// (Plan 022 §2.3). Returns one item per food the user mentioned, or null
  /// if the model isn't loaded / output couldn't be parsed.
  Future<List<ExtractedFoodItem>?> extractFoodItems(String text);

  /// Plan 026 §3 + Plan 027 §5 — combined extract + resolve + estimate in a
  /// single round trip, with combine-vs-split intent.
  ///
  /// The caller pre-fetches a candidate pool from the local DB via alias-
  /// aware FTS; the model picks `food_id` from candidates when one matches,
  /// or returns `estimatedMacros` when no candidate fits. The model also
  /// classifies the intent: `singleDish` means combine items into one log
  /// entry (e.g. "egg with sardines"), `itemsList` means keep them separate
  /// (e.g. "100g rice and 80g chicken").
  Future<ParseFoodResult?> parseFoodWithCandidates(
    String text,
    List<FoodSearchCandidate> candidates,
  );

  /// Parse a food photo (+ optional caption) into log items (Plan 029).
  ///
  /// Vision-only: the model identifies every food on the plate and estimates
  /// each portion + macros in one pass. Items always have a null `food_id`
  /// (no DB candidate pool) and populated `estimatedMacros`. The returned
  /// [PhotoParseResult.status] distinguishes a successful parse from
  /// "no food in image", the per-user daily cap, an unavailable service, and
  /// a generic failure — the caller surfaces each differently.
  ///
  /// Only the cloud tier implements this; on-device and null tiers return
  /// [PhotoParseStatus.unavailable].
  Future<PhotoParseResult> parseFoodFromImage(
    Uint8List imageBytes,
    String mimeType,
    String? caption,
  );

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

  /// Re-rank semantic search [candidates] against the user's [userQuery].
  ///
  /// Returns the picked candidate's `food_id` plus a confidence ∈ [0, 1].
  /// Returns null if the model is unavailable, the response can't be parsed,
  /// or no candidate is a clear winner.
  ///
  /// Implementations should keep prompts small (top-5 names + ids) and
  /// time-bound (≤ 5 s). Used by [NutritionPresenter] when semantic top-1
  /// score is in the "ambiguous" band.
  Future<FoodDisambiguation?> disambiguateFood(
    String userQuery,
    List<FoodSearchCandidate> candidates,
  );

  /// One turn of the chat-logging classifier (Plan 026 §3.3).
  ///
  /// Returns one of three concrete [ClassifierStep]s:
  /// - [StepResolved] when all required fields are filled (≥ 0.6 confidence).
  /// - [StepClarify] when the model needs to ask one targeted question.
  /// - [StepGiveUp] when the model can't pin it down — caller falls back to
  ///   opening the form prefilled with whatever's known.
  ///
  /// Returns null only when the underlying service is unavailable or the
  /// model output couldn't be parsed at all. The caller treats null the
  /// same as [StepGiveUp].
  ///
  /// Implementations MUST validate every named entity against the live
  /// [accounts] / [categories] lists; hallucinated names force the step to
  /// downgrade to [StepGiveUp] before returning.
  Future<ClassifierStep?> runFinanceClassifierStep({
    required List<LedgerChatTurn> conversation,
    required PreparseResult preparse,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required int turnCount,
  });

  void dispose();
}

/// Result of [AiCoachService.disambiguateFood].
class FoodDisambiguation {
  final String foodId;
  final double confidence;
  const FoodDisambiguation({required this.foodId, required this.confidence});
}
