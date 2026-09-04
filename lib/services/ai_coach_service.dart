import 'dart:typed_data';

import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/ai_tool.dart';
import '../models/advisor_event.dart';
import '../models/ai_meal_estimate.dart';
import '../models/ai_parsed_food.dart';
import '../models/extracted_food_item.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/receipt_parse_result.dart';
import '../models/food_parse_result.dart';
import '../models/food_search_candidate.dart';
import '../utils/finance_entry_extraction.dart';

/// Tier of the active AI Coach service.
enum AiCoachTier { onDevice, cloud }

/// Thrown into the [AiCoachService.respond] stream when a response could not
/// be produced. Carries a user-facing message that matches the actual failure
/// (transport vs auth vs rate-limit vs server error) so the UI never blames
/// the user's connection for a failure that wasn't one.
///
/// Failures MUST surface as stream errors, never as yielded text: consumers
/// like the Insight Engine collect yielded tokens as AI content and would
/// otherwise persist the error prose as a coaching insight.
class AiCoachException implements Exception {
  const AiCoachException(this.userMessage);

  /// Short, plain-language explanation safe to show directly in the UI.
  final String userMessage;

  @override
  String toString() => 'AiCoachException: $userMessage';
}

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

  /// Stream the financial advisor's reply (Plan: ai-financial-advisor).
  ///
  /// Uses a stronger cloud model than [respond]. [context] carries the
  /// PHP-formatted financial snapshot ([AiCoachContext.financeSnapshotSummary]) —
  /// the model's only source of numeric truth. [profile] is the user's durable
  /// learned facts (goals, risk tolerance, freeform notes), and [historical] an
  /// optional prior-period benchmark string.
  ///
  /// [tools] is the catalogue this build can execute. It is declared by the
  /// client rather than the backend because the client is what runs them —
  /// every tool acts on data that lives on this device. Pass an empty list for
  /// a plain advisory turn.
  ///
  /// Streams the turn as it is written. A turn is [AdvisorEventKind.start],
  /// zero or more [AdvisorEventKind.delta], then exactly one of
  /// [AdvisorEventKind.end] or [AdvisorEventKind.error] — and a stream that
  /// stops without one of those two has failed, however much text arrived.
  ///
  /// It streams because it must, not for polish: the reply takes tens of
  /// seconds to generate, and the gateway the buffered path sits behind will
  /// not wait more than 30 of them. The finished turn arrives on the terminal
  /// event, so a caller still cannot tell a turn is over until it knows
  /// whether the model asked for a tool.
  ///
  /// Only the cloud tier produces a real answer; the on-device and null tiers
  /// throw [AiCoachException] (the small on-device model can't do this reasoning).
  Stream<AdvisorEvent> adviseFinance({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    String? profile,
    String? historical,
    List<AiTool> tools = const [],
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

  /// Scan a receipt photo (+ optional note) into a single expense.
  ///
  /// Vision-only: the model reads the merchant, grand total, date, and a
  /// category hint the caller resolves against the user's own categories. The
  /// returned [ReceiptParseResult.status] distinguishes a successful scan from
  /// "not a receipt", the daily cap, an unreachable/erroring backend, and an
  /// unavailable service — the caller surfaces each differently.
  ///
  /// Only the cloud tier implements this; on-device and null tiers return
  /// [ReceiptParseStatus.unavailable].
  Future<ReceiptParseResult> parseReceiptFromImage(
    Uint8List imageBytes,
    String mimeType,
    String? note,
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

  /// Extracts every transaction described by [message] in ONE call (Plan 058).
  ///
  /// This is the primary logging path. Unlike [runFinanceClassifierStep], which
  /// sees a single pre-split fragment, this receives the user's whole message —
  /// so context stated once ("in maribank ... all yesterday") reaches every
  /// entry it covers, which is the thing per-fragment classification could not
  /// do however good the model was.
  ///
  /// [now] is injected so relative dates resolve against a testable clock.
  ///
  /// Returns null when the tier is unavailable or the response can't be parsed;
  /// the caller falls back to the regex pipeline rather than showing a
  /// half-read message. Implementations MUST bind every named entity against
  /// the live [accounts] / [categories] lists — a name that doesn't match must
  /// leave that field null and record it in [ExtractedEntry.missing], never
  /// produce an invented id.
  Future<ExtractionResult?> extractFinanceEntries({
    required String message,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required String Function(String categoryId) categoryNameFor,
    DateTime? now,
  });

  void dispose();
}

/// Result of [AiCoachService.disambiguateFood].
class FoodDisambiguation {
  final String foodId;
  final double confidence;
  const FoodDisambiguation({required this.foodId, required this.confidence});
}
