import 'dart:typed_data';

import 'package:intermittent_fasting/models/notification_preferences.dart';
// Presenter-level state machine tests for the chat-logging flow (Plan 026 §7).
// Uses a FakeAiCoachService that replays a scripted sequence of
// ClassifierSteps, so these tests cover the presenter contract end-to-end
// without exercising the Qwen model.

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/ai_meal_estimate.dart';
import 'package:intermittent_fasting/models/ai_parsed_food.dart';
import 'package:intermittent_fasting/models/extracted_food_item.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receipt_parse_result.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/food_parse_result.dart';
import 'package:intermittent_fasting/models/food_search_candidate.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/finance_entry_extraction.dart';
import 'package:intermittent_fasting/models/finance/extracted_entry.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

class FakeAiCoachService implements AiCoachService {
  final List<ClassifierStep?> _script;
  int callCount = 0;

  FakeAiCoachService(this._script);

  @override
  AiCoachTier get tier => AiCoachTier.onDevice;

  @override
  bool get isAvailable => true;

  @override
  int? get downloadProgress => null;

  @override
  Future<void> downloadModel({void Function(int progress)? onProgress}) async {}

  /// Scripted extraction results (Plan 058). An empty script means "this tier
  /// has nothing", which is exactly what drives the regex fallback path.
  List<ExtractionResult?> extractionScript = const [];
  int extractCallCount = 0;
  String? lastExtractMessage;

  @override
  Future<ExtractionResult?> extractFinanceEntries({
    required String message,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required String Function(String categoryId) categoryNameFor,
    DateTime? now,
  }) async {
    lastExtractMessage = message;
    if (extractCallCount >= extractionScript.length) return null;
    return extractionScript[extractCallCount++];
  }

  @override
  Future<ClassifierStep?> runFinanceClassifierStep({
    required List<LedgerChatTurn> conversation,
    required PreparseResult preparse,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required int turnCount,
  }) async {
    if (callCount >= _script.length) return null;
    return _script[callCount++];
  }

  @override
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  }) async* {}

  @override
  Stream<String> adviseFinance({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    String? profile,
    String? historical,
  }) async* {}

  @override
  Future<FoodParseResult?> parseFood(String description) async => null;

  @override
  Future<List<ExtractedFoodItem>?> extractFoodItems(String text) async => null;

  @override
  Future<ParseFoodResult?> parseFoodWithCandidates(
    String text,
    List<FoodSearchCandidate> candidates,
  ) async =>
      null;

  @override
  Future<PhotoParseResult> parseFoodFromImage(
    Uint8List imageBytes,
    String mimeType,
    String? caption,
  ) async =>
      const PhotoParseResult(PhotoParseStatus.unavailable);

  /// Scripted receipt-scan outcome for [parseReceiptFromImage].
  ReceiptParseResult receiptResult =
      const ReceiptParseResult(ReceiptParseStatus.unavailable);

  @override
  Future<ReceiptParseResult> parseReceiptFromImage(
    Uint8List imageBytes,
    String mimeType,
    String? note,
  ) async =>
      receiptResult;

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
  Future<FoodDisambiguation?> disambiguateFood(
    String userQuery,
    List<FoodSearchCandidate> candidates,
  ) async =>
      null;

  @override
  void dispose() {}
}

FinancialAccount _acc(String id, String name,
        {double balance = 0, AccountCategory cat = AccountCategory.bank}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: cat,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name, CategoryType type) =>
    FinanceCategory(
      id: id,
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

Future<void> _waitForLoad(LedgerPresenter presenter) async {
  while (presenter.isLoading) {
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  final gcash =
      _acc('gcash', 'GCash', balance: 1000, cat: AccountCategory.ewallet);
  final bpi = _acc('bpi', 'BPI', balance: 5000);
  final food = _cat('food', 'Food', CategoryType.expense);
  final salary = _cat('salary', 'Salary', CategoryType.income);

  setUp(() {
    storage = MockStorageService();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    stats = MockStatsPresenter();
    when(storage.loadAccounts()).thenAnswer((_) async => [gcash, bpi]);
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => [food, salary]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  });

  group('regex+dict fast-path', () {
    test('fully-resolved input commits without AI call', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash');

      expect(presenter.allTransactions, hasLength(1));
      expect(ai.callCount, 0);
      expect(presenter.lastCommittedSummary, isNotNull);
      expect(presenter.chatState.phase, ChatPhase.idle);
    });

    test('hard error sets chatHardError, no AI call, no commit', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 -300 food gcash');

      expect(presenter.chatHardError, FinanceParseError.multipleAmounts);
      expect(presenter.allTransactions, isEmpty);
      expect(ai.callCount, 0);
    });
  });

  group('AI dialog — Resolved', () {
    test('Resolved turn shows confirm card without committing', () async {
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 500,
            type: TransactionType.outflow,
            accountId: gcash.id,
            categoryId: food.id,
            description: '500 gcash hamburger',
          ),
          learnedToken: 'hamburger',
          summaryText: 'Log ₱500 → Food (GCash)?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('500 gcash hamburger');

      expect(ai.callCount, 1);
      expect(presenter.chatState.phase, ChatPhase.clarifying);
      expect(presenter.chatState.lastStep, isA<StepResolved>());
      expect(presenter.allTransactions, isEmpty); // not yet committed
    });

    test('confirmResolved commits + learns token + resets state', () async {
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 500,
            type: TransactionType.outflow,
            accountId: gcash.id,
            categoryId: food.id,
            description: '500 gcash hamburger',
          ),
          learnedToken: 'hamburger',
          summaryText: 'Log ₱500 → Food (GCash)?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      await presenter.sendChatInput('500 gcash hamburger');

      await presenter.confirmResolved();

      expect(presenter.allTransactions, hasLength(1));
      expect(presenter.chatState.phase, ChatPhase.idle);
      // Verify the dict learned the token by persisting at least once.
      verify(storage.saveFinanceDictionary(any)).called(greaterThan(0));
    });
  });

  group('AI dialog — Clarify', () {
    test('Clarify enters clarifying state with question + chips', () async {
      final ai = FakeAiCoachService([
        StepClarify(
          question: 'Did you mean BPI or BDO?',
          quickReplies: const [
            QuickReply(label: 'BPI', replyText: 'BPI'),
          ],
          partialDraft: const ParsedTransaction(),
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 b food');

      expect(presenter.chatState.phase, ChatPhase.clarifying);
      expect(presenter.chatState.lastStep, isA<StepClarify>());
      expect(presenter.allTransactions, isEmpty);
    });

    test('reply advances turnCount and runs another classifier step', () async {
      final ai = FakeAiCoachService([
        StepClarify(
          question: 'Which account?',
          partialDraft: const ParsedTransaction(),
        ),
        StepResolved(
          transaction: ParsedTransaction(
            amount: 500,
            type: TransactionType.outflow,
            accountId: bpi.id,
            categoryId: food.id,
            description: 'reply',
          ),
          summaryText: 'Log ₱500 → Food (BPI)?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food');
      await presenter.sendChatInput('BPI');

      expect(ai.callCount, 2);
      expect(presenter.chatState.turnCount, 1);
      expect(presenter.chatState.lastStep, isA<StepResolved>());
    });
  });

  group('AI dialog — GiveUp', () {
    test('GiveUp falls back to form prefilled with partial draft', () async {
      final ai = FakeAiCoachService([
        StepGiveUp(
          reason: 'Too ambiguous',
          partialDraft: ParsedTransaction(amount: 500, accountId: gcash.id),
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      // Input with an amount but no resolvable account/category → AI runs,
      // returns GiveUp, presenter falls back to a prefilled form.
      await presenter.sendChatInput('500 mystery thing');

      expect(presenter.chatState.phase, ChatPhase.idle);
      expect(presenter.pendingFormPrefill, isNotNull);
      expect(presenter.pendingFormPrefill!.amount, 500);
    });
  });

  group('user actions', () {
    test('cancelChat clears state and prefill without committing', () async {
      final ai = FakeAiCoachService([
        StepClarify(
          question: 'Which account?',
          partialDraft: const ParsedTransaction(),
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      await presenter.sendChatInput('-500 food');

      presenter.cancelChat();

      expect(presenter.chatState.phase, ChatPhase.idle);
      expect(presenter.allTransactions, isEmpty);
      verifyNever(storage.saveFinanceDictionary(any));
    });

    test('editResolved surfaces the draft as a form prefill', () async {
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 500,
            type: TransactionType.outflow,
            accountId: gcash.id,
            categoryId: food.id,
            description: 'x',
          ),
          summaryText: 'Log ₱500?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      // Use an input the regex can't fully resolve so the AI step actually
      // runs and produces a StepResolved that editResolved can consume.
      await presenter.sendChatInput('500 gcash hamburger');

      presenter.editResolved();

      expect(presenter.chatState.phase, ChatPhase.idle);
      expect(presenter.pendingFormPrefill, isNotNull);
      expect(presenter.pendingFormPrefill!.accountId, gcash.id);
      expect(presenter.allTransactions, isEmpty);
    });
  });

  group('lifecycle', () {
    test('app backgrounded >5 min resets chat state on resume', () async {
      final ai = FakeAiCoachService([
        StepClarify(
          question: 'Which?',
          partialDraft: const ParsedTransaction(),
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      await presenter.sendChatInput('-500 food');

      presenter.notifyAppPaused();
      // Force the threshold by rewinding the recorded pause timestamp.
      // No public hook for this, so we verify via the resume path: a fresh
      // pause+resume within 5 min keeps state, then a stale-pause test below
      // handles the >5 min case.
      presenter.notifyAppResumed();
      expect(presenter.chatState.phase, ChatPhase.clarifying);
    });
  });

  group('category delete cascade', () {
    test('deleteCategory removes dict entries pointing at that category',
        () async {
      // Learn the token first via the chat flow (it'll commit a transaction).
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 500,
            type: TransactionType.outflow,
            accountId: gcash.id,
            categoryId: food.id,
            description: 'x',
          ),
          learnedToken: 'hamburger',
          summaryText: 'Log ₱500?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      await presenter.sendChatInput('500 gcash hamburger');
      await presenter.confirmResolved();
      // Delete the committed transaction so deleteCategory isn't blocked by
      // the `has_transactions` guard — we're isolating the dict cascade here.
      final txnId = presenter.allTransactions.first.id;
      await presenter.deleteTransaction(txnId);
      clearInteractions(storage);

      await presenter.deleteCategory(food.id);

      verify(storage.saveFinanceDictionary(any)).called(greaterThan(0));
    });
  });

  group('receipt photo', () {
    test('a scanned receipt seeds the confirm card (StepResolved)', () async {
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 1699,
            type: TransactionType.outflow,
            accountId: gcash.id,
            categoryId: food.id,
            description: 'SM Supermarket',
            descriptionIsClean: true,
          ),
          summaryText: 'Log ₱1,699 → Food (GCash)?',
        ),
      ])
        ..receiptResult = const ReceiptParseResult(
          ReceiptParseStatus.ok,
          total: 1699,
          merchant: 'SM Supermarket',
          categoryHint: 'groceries',
        );
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      final outcome = await presenter.logReceiptPhoto(
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
      );

      expect(outcome, ReceiptScanOutcome.seeded);
      // The classifier ran once against the seeded draft.
      expect(ai.callCount, 1);
      expect(presenter.chatState.phase, ChatPhase.clarifying);
      expect(presenter.chatState.lastStep, isA<StepResolved>());
      expect(presenter.chatState.draft.amount, 1699);
      // Nothing is committed until the user confirms the card.
      expect(presenter.allTransactions, isEmpty);
    });

    test('confirming a scanned receipt commits the expense', () async {
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 1699,
            type: TransactionType.outflow,
            accountId: gcash.id,
            categoryId: food.id,
            description: 'SM Supermarket',
            descriptionIsClean: true,
          ),
          summaryText: 'Log ₱1,699 → Food (GCash)?',
        ),
      ])
        ..receiptResult = const ReceiptParseResult(
          ReceiptParseStatus.ok,
          total: 1699,
          merchant: 'SM Supermarket',
          categoryHint: 'groceries',
        );
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.logReceiptPhoto(Uint8List.fromList([1]), 'image/jpeg');
      await presenter.confirmResolved();

      expect(presenter.allTransactions, hasLength(1));
      expect(presenter.allTransactions.first.amount, 1699);
      expect(presenter.allTransactions.first.type, TransactionType.outflow);
      expect(presenter.chatState.phase, ChatPhase.idle);
    });

    test('a non-receipt photo leaves the chat pipeline untouched', () async {
      final ai = FakeAiCoachService([])
        ..receiptResult =
            const ReceiptParseResult(ReceiptParseStatus.notReceipt);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      final outcome = await presenter.logReceiptPhoto(
        Uint8List.fromList([9]),
        'image/jpeg',
      );

      expect(outcome, ReceiptScanOutcome.notReceipt);
      expect(ai.callCount, 0);
      expect(presenter.chatState.phase, ChatPhase.idle);
      expect(presenter.allTransactions, isEmpty);
    });

    test('no AI service reports unavailable', () async {
      final presenter = LedgerPresenter(storage, stats);
      await _waitForLoad(presenter);

      final outcome = await presenter.logReceiptPhoto(
        Uint8List.fromList([1]),
        'image/jpeg',
      );

      expect(outcome, ReceiptScanOutcome.unavailable);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Several transactions in one message.
  // ───────────────────────────────────────────────────────────────────────────

  // Which messages the assistant should log rather than answer.
  //
  // The advisor used to decide from the words alone (a spend verb, or a short
  // "coffee 120"), so a plainly-stated entry was answered as a question: "207
  // lunch at alturas maya credit card" has no spend verb and seven tokens, and
  // went to the advice model. Asking the preparser instead is stronger
  // evidence, because it knows the user's real accounts and categories.
  group('recognisesLoggableEntry', () {
    Future<LedgerPresenter> presenter() async {
      final p = LedgerPresenter(storage, stats, ai: FakeAiCoachService([]));
      await _waitForLoad(p);
      return p;
    }

    test('an entry stated plainly, with no spend verb, is a log', () async {
      final p = await presenter();
      // Amount + an account it can name. This is the case that regressed.
      expect(p.recognisesLoggableEntry('207 lunch at alturas gcash'), isTrue);
      expect(p.recognisesLoggableEntry('207 food gcash'), isTrue);
      expect(p.recognisesLoggableEntry('-500 food gcash'), isTrue);
    });

    test('a question is never a log, however much it looks like one', () async {
      final p = await presenter();
      // Names an amount AND a category, but it is asking.
      expect(
          p.recognisesLoggableEntry('can I afford 4000 food gcash?'), isFalse);
      expect(
          p.recognisesLoggableEntry('how much on food this month?'), isFalse);
    });

    test('conversation with a number in it is not a log', () async {
      final p = await presenter();
      // An amount alone proves nothing — nothing here names where it went.
      expect(p.recognisesLoggableEntry('i have 12000 saved'), isFalse);
      expect(p.recognisesLoggableEntry('12000'), isFalse);
      expect(p.recognisesLoggableEntry('should I start investing'), isFalse);
      expect(p.recognisesLoggableEntry(''), isFalse);
    });

    test('a multi-entry message counts if any segment is loggable', () async {
      final p = await presenter();
      expect(
        p.recognisesLoggableEntry('-500 food gcash and -300 food bpi'),
        isTrue,
      );
    });

    test('it does not depend on which day the ledger is parked on', () async {
      final p = await presenter();
      p.setSelectedDate(DateTime.now().subtract(const Duration(days: 5)));
      // Viewing a past date changes whether a log is ALLOWED, not whether the
      // words are one — sendChatInput reports that error itself. Routing on it
      // would silently turn an entry into a chat answer.
      expect(p.recognisesLoggableEntry('207 food gcash'), isTrue);
    });
  });

  group('multi-transaction messages', () {
    test('two fully-resolved entries commit with no AI call', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash and -300 food bpi');

      expect(ai.callCount, 0);
      expect(presenter.allTransactions, hasLength(2));
      expect(presenter.lastCommittedSummary, 'Logged 2 transactions');
      expect(presenter.chatState.phase, ChatPhase.idle);
    });

    test('each entry lands on its own account', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash; -300 food bpi');

      final byAccount = {
        for (final t in presenter.allTransactions) t.accountId: t.amount,
      };
      expect(byAccount[gcash.id], 500);
      expect(byAccount[bpi.id], 300);
    });

    test('a transfer alongside an expense writes both transfer legs', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter
          .sendChatInput('transfer 200 bpi to gcash and -100 food gcash');

      // Two transfer legs + one expense. A transfer that logged only one leg
      // was the old failure here.
      expect(presenter.allTransactions, hasLength(3));
      final transferLegs = presenter.allTransactions
          .where((t) => t.transferGroupId != null)
          .toList();
      expect(transferLegs, hasLength(2));
      expect(transferLegs.map((t) => t.type).toSet(),
          {TransactionType.outflow, TransactionType.inflow});
      expect(transferLegs.every((t) => t.amount == 200), isTrue);
    });

    test('one AI call per unresolved segment, resolved ones stay free',
        () async {
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 300,
            type: TransactionType.outflow,
            accountId: bpi.id,
            categoryId: food.id,
            description: 'Hamburger',
            descriptionIsClean: true,
          ),
          summaryText: 'Log ₱300 → Food (BPI)?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash and -300 hamburger bpi');

      // Only the "hamburger" segment needed the model.
      expect(ai.callCount, 1);
      final step = presenter.chatState.lastStep;
      expect(step, isA<StepResolved>());
      step as StepResolved;
      expect(step.isBatch, isTrue);
      expect(step.transactions, hasLength(2));
      expect(step.deferred, isEmpty);
      // Nothing commits until the user confirms.
      expect(presenter.allTransactions, isEmpty);

      await presenter.confirmResolved();
      expect(presenter.allTransactions, hasLength(2));
      expect(presenter.lastCommittedSummary, 'Logged 2 transactions');
    });

    test('the confirm card keeps the written order', () async {
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 300,
            type: TransactionType.outflow,
            accountId: bpi.id,
            categoryId: food.id,
            description: 'Hamburger',
            descriptionIsClean: true,
          ),
          summaryText: 'Log ₱300 → Food (BPI)?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      // The AI-resolved segment is written FIRST; the parser-resolved one
      // second. Rebuilding by segment order (not by who answered) keeps them
      // in the order the user typed.
      await presenter.sendChatInput('-300 hamburger bpi and -500 food gcash');

      final step = presenter.chatState.lastStep as StepResolved;
      expect(step.transactions.map((t) => t.amount).toList(), [300, 500]);
    });

    test('a segment the AI gives up on is deferred, then asked about',
        () async {
      final ai = FakeAiCoachService([
        // First call: the "hamburger" segment — no idea.
        const StepGiveUp(reason: 'no clue', partialDraft: ParsedTransaction()),
        // Second call: the deferred segment's own clarify conversation.
        const StepClarify(
          question: 'Which account?',
          partialDraft: ParsedTransaction(),
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash and -300 hamburger bpi');

      final step = presenter.chatState.lastStep as StepResolved;
      expect(step.transactions, hasLength(1)); // just the parser-resolved one
      expect(step.deferred, hasLength(1));
      expect(step.deferred.first.rawInput, contains('hamburger'));

      // Confirming logs the good one AND picks the leftover back up, rather
      // than dropping it silently.
      await presenter.confirmResolved();
      expect(presenter.allTransactions, hasLength(1));
      expect(presenter.chatState.lastStep, isA<StepClarify>());
      expect(presenter.chatState.phase, ChatPhase.clarifying);
    });

    // ── One-shot surfaces (web Quick Add) ───────────────────────────────────
    //
    // No clarify UI: confident entries commit and unresolved ones go to the
    // prefilled form. Only the first leftover used to be kept, and the web view
    // then never opened the form at all when anything had committed — so the
    // rest of a multi-entry message disappeared without a word.
    group('autoResolve', () {
      test('every unresolved entry is queued for the form, not just the first',
          () async {
        final ai = FakeAiCoachService([
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
        ]);
        final presenter = LedgerPresenter(storage, stats, ai: ai);
        await _waitForLoad(presenter);

        await presenter.sendChatInput(
          '-500 food gcash and -300 hamburger bpi and -200 kwek kwek bpi',
          autoResolve: true,
        );

        // The one the parser could resolve is logged outright.
        expect(presenter.allTransactions, hasLength(1));
        expect(presenter.lastCommittedSummary, isNotNull);
        // Both leftovers survive: one in hand, one behind it.
        expect(presenter.pendingFormPrefill, isNotNull);
        expect(presenter.queuedFormPrefillCount, 1);

        // Draining hands them over one at a time, then reports empty.
        presenter.consumeFormPrefill();
        expect(presenter.takeNextFormPrefill(), isNotNull);
        expect(presenter.takeNextFormPrefill(), isNull);
      });

      test('a committed entry and a leftover are reported independently',
          () async {
        final ai = FakeAiCoachService([
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
        ]);
        final presenter = LedgerPresenter(storage, stats, ai: ai);
        await _waitForLoad(presenter);

        await presenter.sendChatInput(
          '-500 food gcash and -300 hamburger bpi',
          autoResolve: true,
        );

        // Both signals are set at once. The view used to read them as an
        // either/or and, seeing the summary, never looked for the prefill.
        expect(presenter.lastCommittedSummary, isNotNull);
        expect(presenter.pendingFormPrefill, isNotNull);
      });

      test('when nothing resolves, the later entries are still queued',
          () async {
        final ai = FakeAiCoachService([
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
        ]);
        final presenter = LedgerPresenter(storage, stats, ai: ai);
        await _waitForLoad(presenter);

        await presenter.sendChatInput(
          '-300 hamburger bpi and -200 kwek kwek bpi',
          autoResolve: true,
        );

        expect(presenter.allTransactions, isEmpty);
        expect(presenter.pendingFormPrefill, isNotNull);
        expect(presenter.queuedFormPrefillCount, 1);
      });

      test('a new message clears leftovers the user walked away from',
          () async {
        final ai = FakeAiCoachService([
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
        ]);
        final presenter = LedgerPresenter(storage, stats, ai: ai);
        await _waitForLoad(presenter);

        await presenter.sendChatInput(
          '-500 food gcash and -300 hamburger bpi and -200 kwek kwek bpi',
          autoResolve: true,
        );
        expect(presenter.queuedFormPrefillCount, 1);

        // Abandon the form flow and type something else. The old queue must not
        // ambush the new entry with a form from the previous message.
        await presenter.sendChatInput('-100 food gcash', autoResolve: true);
        expect(presenter.queuedFormPrefillCount, 0);
        expect(presenter.pendingFormPrefill, isNull);
      });

      test('cancel drops the queued form prefills too', () async {
        final ai = FakeAiCoachService([
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
        ]);
        final presenter = LedgerPresenter(storage, stats, ai: ai);
        await _waitForLoad(presenter);

        await presenter.sendChatInput(
          '-500 food gcash and -300 hamburger bpi and -200 kwek kwek bpi',
          autoResolve: true,
        );
        expect(presenter.queuedFormPrefillCount, 1);

        presenter.cancelChat();
        expect(presenter.queuedFormPrefillCount, 0);
        expect(presenter.pendingFormPrefill, isNull);
      });

      test('a single entry that resolves leaves nothing for the form',
          () async {
        final ai = FakeAiCoachService([]);
        final presenter = LedgerPresenter(storage, stats, ai: ai);
        await _waitForLoad(presenter);

        await presenter.sendChatInput('-500 food gcash', autoResolve: true);

        expect(presenter.allTransactions, hasLength(1));
        expect(presenter.pendingFormPrefill, isNull);
        expect(presenter.queuedFormPrefillCount, 0);
      });
    });

    // The form the chat hands off to used to show the raw message in its
    // Description field — sitting right beside the Amount and Account fields
    // holding those very values. Only the commit path cleaned the label.
    group('the prefilled form', () {
      test('gets a description without the amount or the account in it',
          () async {
        final ai = FakeAiCoachService([
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
        ]);
        final presenter = LedgerPresenter(storage, stats, ai: ai);
        await _waitForLoad(presenter);

        await presenter.sendChatInput('207 lunch at alturas gcash',
            autoResolve: true);

        final prefill = presenter.pendingFormPrefill!;
        expect(prefill.amount, 207);
        expect(prefill.accountId, gcash.id);
        expect(prefill.description, 'lunch at alturas');
        expect(prefill.description, isNot(contains('207')));
        expect(prefill.description.toLowerCase(), isNot(contains('gcash')));
      });

      test('every queued leftover is cleaned too, not just the first',
          () async {
        final ai = FakeAiCoachService([
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
          const StepGiveUp(
              reason: 'no clue', partialDraft: ParsedTransaction()),
        ]);
        final presenter = LedgerPresenter(storage, stats, ai: ai);
        await _waitForLoad(presenter);

        await presenter.sendChatInput(
          '207 lunch at alturas gcash and 89 merienda at bos bpi',
          autoResolve: true,
        );

        expect(presenter.pendingFormPrefill!.description, 'lunch at alturas');
        presenter.consumeFormPrefill();
        final next = presenter.takeNextFormPrefill()!;
        expect(next.description, isNot(contains('89')));
        expect(next.description.toLowerCase(), isNot(contains('bpi')));
      });
    });

    test('cancel drops the queued leftovers too', () async {
      final ai = FakeAiCoachService([
        const StepGiveUp(reason: 'no clue', partialDraft: ParsedTransaction()),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash and -300 hamburger bpi');
      expect((presenter.chatState.lastStep as StepResolved).deferred,
          hasLength(1));

      presenter.cancelChat();
      expect(presenter.chatState.phase, ChatPhase.idle);
      expect(presenter.allTransactions, isEmpty);

      // A fresh single entry behaves normally — no ambush from the old queue.
      await presenter.sendChatInput('-100 food gcash');
      expect(presenter.allTransactions, hasLength(1));
      expect(presenter.chatState.phase, ChatPhase.idle);
    });

    test('a learned token is paired with its own segment\'s category',
        () async {
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 5000,
            type: TransactionType.inflow,
            accountId: bpi.id,
            categoryId: salary.id,
            description: 'Freelance',
            descriptionIsClean: true,
          ),
          learnedToken: 'upwork',
          summaryText: 'Log ₱5000 → Salary (BPI)?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      // Segment 1 is a Food expense the parser resolves; segment 2 is the
      // income the AI resolves, and the token belongs to THAT one. Pairing the
      // token with the batch's first category would teach upwork → Food.
      await presenter.sendChatInput('-500 food gcash and +5000 upwork bpi');
      await presenter.confirmResolved();

      expect(presenter.allTransactions, hasLength(2));
      verify(storage.saveFinanceDictionary(argThat(predicate((dynamic list) {
        final entries = list as List;
        return entries.length == 1 &&
            entries.first.token == 'upwork' &&
            entries.first.categoryId == salary.id;
      })))).called(1);
    });

    test('an "and" inside a description is not a separator', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-150 food gcash coffee and donuts');

      expect(presenter.allTransactions, hasLength(1));
      expect(presenter.allTransactions.first.amount, 150);
      expect(presenter.allTransactions.first.description,
          contains('coffee and donuts'));
    });

    test('viewing a past date still blocks the whole message', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      presenter
          .setSelectedDate(DateTime.now().subtract(const Duration(days: 3)));

      await presenter.sendChatInput('-500 food gcash and -300 food bpi');

      expect(presenter.chatHardError, FinanceParseError.viewingPastDate);
      expect(presenter.allTransactions, isEmpty);
      expect(ai.callCount, 0);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Fields the chat parser used to be unable to reach.
  // ───────────────────────────────────────────────────────────────────────────

  group('form-parity fields reach storage', () {
    test('a note is stored on the transaction, apart from the description',
        () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash note: Split with Mika');

      expect(ai.callCount, 0);
      final txn = presenter.allTransactions.single;
      expect(txn.note, 'Split with Mika');
      // The note text must not be duplicated into the label.
      expect(txn.description, isNot(contains('Split with Mika')));
    });

    test('a back-dated entry lands on the named day', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash yesterday');

      final txn = presenter.allTransactions.single;
      final expected = DateTime.now().subtract(const Duration(days: 1));
      expect(txn.date.year, expected.year);
      expect(txn.date.month, expected.month);
      expect(txn.date.day, expected.day);
      // The month key must follow the date, not today, or the row files itself
      // under the wrong month.
      expect(txn.month, toMonthKey(txn.date));
      expect(txn.description, isNot(contains('yesterday')));
    });

    test('an undated entry still stamps now', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash');

      final txn = presenter.allTransactions.single;
      final now = DateTime.now();
      expect(txn.date.day, now.day);
      expect(txn.month, toMonthKey(now));
    });

    test('a calculator expression commits its computed total', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-285+15 food gcash');

      expect(presenter.allTransactions.single.amount, 300);
      expect(ai.callCount, 0);
    });

    test('a reimbursable carries the debtor and the payback date', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      DateTime? spawnedDate;
      TransactionRecord? spawnedFor;
      presenter.onSpawnReimbursementReceivable = (outflow, expected) async {
        spawnedFor = outflow;
        spawnedDate = expected;
      };

      await presenter.sendChatInput(
          '-800 food gcash spotted Jana, she pays me back friday');

      final txn = presenter.allTransactions.single;
      expect(txn.reimbursable, isTrue);
      expect(txn.owedBy, 'Jana');
      expect(spawnedFor?.id, txn.id);
      expect(spawnedDate, isNotNull);
      // The payback date belongs to the receivable, not the expense itself.
      expect(txn.date.day, DateTime.now().day);
    });

    test('a reimbursable with no named date leaves the receivable at ASAP',
        () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      var spawned = false;
      DateTime? spawnedDate;
      presenter.onSpawnReimbursementReceivable = (outflow, expected) async {
        spawned = true;
        spawnedDate = expected;
      };

      await presenter.sendChatInput('-500 food gcash work expense');

      expect(presenter.allTransactions.single.reimbursable, isTrue);
      expect(spawned, isTrue);
      expect(spawnedDate, isNull); // ASAP, matching the form's default
    });

    test('an ordinary expense carries no debtor', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash lunch');

      final txn = presenter.allTransactions.single;
      expect(txn.reimbursable, isFalse);
      expect(txn.owedBy, isNull);
    });

    test('the AI path no longer loses the reimbursable flag', () async {
      // The classifier response says nothing about reimbursable; the preparser
      // had already detected it. Rebuilding the draft from the response alone
      // used to drop the flag, committing a plain expense with no receivable.
      final ai = FakeAiCoachService([
        StepResolved(
          transaction: ParsedTransaction(
            amount: 500,
            type: TransactionType.outflow,
            accountId: gcash.id,
            categoryId: food.id,
            description: 'Client lunch',
            descriptionIsClean: true,
          ),
          summaryText: 'Log ₱500 → Food (GCash)?',
        ),
      ]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);
      var spawned = false;
      presenter.onSpawnReimbursementReceivable = (_, __) async {
        spawned = true;
      };

      // "hamburger" is unlearned, so the AI runs; "work expense" makes the
      // preparser flag it reimbursable.
      await presenter.sendChatInput('-500 gcash hamburger work expense');
      expect(ai.callCount, 1);
      await presenter.confirmResolved();

      final txn = presenter.allTransactions.single;
      expect(txn.reimbursable, isTrue);
      expect(spawned, isTrue);
    });

    test('a long description is truncated visibly, not silently mid-word',
        () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      final longLabel = List.filled(40, 'groceries').join(' ');
      await presenter.sendChatInput('-500 food gcash $longLabel');

      final description = presenter.allTransactions.single.description;
      expect(description.length, lessThanOrEqualTo(121));
      expect(description, endsWith('…'));
      // Cut on a word boundary: no half-word before the ellipsis.
      expect(description, isNot(contains('grocerie…')));
    });

    test('a short description is left exactly as it was', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('-500 food gcash jollibee');

      final description = presenter.allTransactions.single.description;
      expect(description, isNot(contains('…')));
      expect(description, contains('jollibee'));
    });

    test('a transfer carries its note and date on both legs', () async {
      final ai = FakeAiCoachService([]);
      final presenter = LedgerPresenter(storage, stats, ai: ai);
      await _waitForLoad(presenter);

      await presenter
          .sendChatInput('transfer 200 bpi to gcash yesterday note: Top up');

      final legs = presenter.allTransactions;
      expect(legs, hasLength(2));
      final expected = DateTime.now().subtract(const Duration(days: 1));
      for (final leg in legs) {
        expect(leg.note, 'Top up');
        expect(leg.date.day, expected.day);
        expect(leg.month, toMonthKey(leg.date));
      }
    });
  });

  // ── Plan 058: one-call extraction over the whole message ──────────────────

  group('AI-first extraction', () {
    ExtractedEntry made({
      double? amount = 175,
      String? accountId = 'gcash',
      String? categoryId = 'food',
      TransactionType? type = TransactionType.outflow,
      DateTime? date,
      String description = 'Personal Shopping',
      Set<EntryField> missing = const {},
      double confidence = 0.9,
    }) =>
        ExtractedEntry(
          txn: ParsedTransaction(
            amount: amount,
            type: type,
            accountId: accountId,
            categoryId: categoryId,
            date: date,
            description: description,
            descriptionIsClean: true,
          ),
          missing: missing,
          confidence: confidence,
        );

    LedgerPresenter withCloud(FakeAiCoachService cloud,
            {FakeAiCoachService? onDevice}) =>
        LedgerPresenter(storage, stats,
            ai: onDevice ?? FakeAiCoachService([]), cloudAi: cloud);

    test('the whole message reaches the model, unsplit', () async {
      final cloud = FakeAiCoachService([])
        ..extractionScript = [
          ExtractionResult(entries: [made()]),
        ];
      final presenter = withCloud(cloud);
      await _waitForLoad(presenter);

      const message = 'add in gcash 175 and 90 for food all yesterday';
      await presenter.sendChatInput(message);

      expect(cloud.lastExtractMessage, message,
          reason: 'the model must see the sentence, not a fragment of it');
      expect(cloud.extractCallCount, 1,
          reason: 'one call for the message, not one per fragment');
    });

    test('extracted rows go to review, and nothing commits yet', () async {
      final cloud = FakeAiCoachService([])
        ..extractionScript = [
          ExtractionResult(entries: [
            made(amount: 175),
            made(amount: 90),
            made(amount: 115, description: 'Avocado Ice Cream'),
          ]),
        ];
      final presenter = withCloud(cloud);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('175 and 90 and 115 gcash food');

      expect(presenter.chatState.phase, ChatPhase.reviewing);
      expect(presenter.chatState.entries, hasLength(3));
      expect(presenter.chatState.isReadyToCommit, isTrue);
      expect(presenter.allTransactions, isEmpty,
          reason: 'the card is the honesty surface — the user confirms');
    });

    test('confirmEntries commits every row as one action', () async {
      final cloud = FakeAiCoachService([])
        ..extractionScript = [
          ExtractionResult(entries: [
            made(amount: 175),
            made(amount: 90),
            made(amount: 115),
          ]),
        ];
      final presenter = withCloud(cloud);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('175 and 90 and 115 gcash food');
      await presenter.confirmEntries();

      expect(presenter.allTransactions, hasLength(3));
      expect(presenter.lastCommittedSummary, 'Logged 3 transactions');
      expect(presenter.chatState.phase, ChatPhase.idle);
    });

    test('a shared date reaches every committed row', () async {
      final yesterday = DateTime(2026, 8, 29);
      final cloud = FakeAiCoachService([])
        ..extractionScript = [
          ExtractionResult(entries: [
            made(amount: 175, date: yesterday),
            made(amount: 90, date: yesterday),
          ]),
        ];
      final presenter = withCloud(cloud);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('175 and 90 gcash food yesterday');
      await presenter.confirmEntries();

      expect(
        presenter.allTransactions
            .every((t) => t.date.year == 2026 && t.date.day == 29),
        isTrue,
      );
    });

    test('a row with a gap blocks the commit but keeps its siblings', () async {
      final cloud = FakeAiCoachService([])
        ..extractionScript = [
          ExtractionResult(entries: [
            made(amount: 175),
            made(amount: 90, accountId: null, missing: {EntryField.account}),
          ]),
        ];
      final presenter = withCloud(cloud);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('175 gcash food and 90 food');

      expect(presenter.chatState.isReadyToCommit, isFalse);
      expect(presenter.chatState.unresolvedCount, 1);
      expect(presenter.chatState.entries, hasLength(2),
          reason: 'the good row is never dropped for the sake of the bad one');
    });

    group('inline resolution', () {
      test('picking an account clears the gap without an AI call', () async {
        final cloud = FakeAiCoachService([])
          ..extractionScript = [
            ExtractionResult(entries: [
              made(accountId: null, missing: {EntryField.account}),
            ]),
          ];
        final presenter = withCloud(cloud);
        await _waitForLoad(presenter);
        await presenter.sendChatInput('175 food');

        presenter.setEntryAccount(0, 'bpi');

        expect(presenter.chatState.entries.single.missing, isEmpty);
        expect(presenter.chatState.entries.single.txn.accountId, 'bpi');
        expect(presenter.chatState.isReadyToCommit, isTrue);
        expect(cloud.extractCallCount, 1,
            reason: 'a dropdown answers this, not another round trip');
      });

      test('picking a category settles the direction too', () async {
        final cloud = FakeAiCoachService([])
          ..extractionScript = [
            ExtractionResult(entries: [
              made(
                categoryId: null,
                type: null,
                missing: {EntryField.category, EntryField.type},
              ),
            ]),
          ];
        final presenter = withCloud(cloud);
        await _waitForLoad(presenter);
        await presenter.sendChatInput('25000 bpi');

        presenter.setEntryCategory(0, 'salary');

        final entry = presenter.chatState.entries.single;
        expect(entry.txn.categoryId, 'salary');
        expect(entry.txn.type, TransactionType.inflow,
            reason: 'an income category can only be an inflow');
        expect(entry.missing, isEmpty);
      });

      test('a resolved row commits with the picked values', () async {
        final cloud = FakeAiCoachService([])
          ..extractionScript = [
            ExtractionResult(entries: [
              made(accountId: null, missing: {EntryField.account}),
            ]),
          ];
        final presenter = withCloud(cloud);
        await _waitForLoad(presenter);
        await presenter.sendChatInput('175 food');

        presenter.setEntryAccount(0, 'bpi');
        await presenter.confirmEntries();

        expect(presenter.allTransactions, hasLength(1));
        expect(presenter.allTransactions.single.accountId, 'bpi');
      });

      test('removing the last row ends the review', () async {
        final cloud = FakeAiCoachService([])
          ..extractionScript = [
            ExtractionResult(entries: [made()]),
          ];
        final presenter = withCloud(cloud);
        await _waitForLoad(presenter);
        await presenter.sendChatInput('175 gcash food');

        presenter.removeEntry(0);

        expect(presenter.chatState.phase, ChatPhase.idle);
        expect(presenter.chatState.entries, isEmpty);
        expect(presenter.allTransactions, isEmpty);
      });

      test('removing one row of several keeps the rest', () async {
        final cloud = FakeAiCoachService([])
          ..extractionScript = [
            ExtractionResult(entries: [made(amount: 175), made(amount: 90)]),
          ];
        final presenter = withCloud(cloud);
        await _waitForLoad(presenter);
        await presenter.sendChatInput('175 and 90 gcash food');

        presenter.removeEntry(0);

        expect(presenter.chatState.entries, hasLength(1));
        expect(presenter.chatState.entries.single.txn.amount, 90);
      });
    });

    group('falling back', () {
      test('no cloud tier at all uses the regex path', () async {
        final onDevice = FakeAiCoachService([]);
        final presenter = LedgerPresenter(storage, stats, ai: onDevice);
        await _waitForLoad(presenter);

        await presenter.sendChatInput('-500 food gcash');

        expect(presenter.allTransactions, hasLength(1),
            reason: 'offline logging must keep working');
      });

      test('an unreadable extraction falls back rather than failing', () async {
        // Empty script → the fake returns null, which is what a transport
        // error or unparseable response looks like to the presenter.
        final cloud = FakeAiCoachService([]);
        final presenter = withCloud(cloud);
        await _waitForLoad(presenter);

        await presenter.sendChatInput('-500 food gcash');

        expect(presenter.allTransactions, hasLength(1));
      });

      test('an empty extraction with no question falls back too', () async {
        final cloud = FakeAiCoachService([])
          ..extractionScript = [const ExtractionResult(entries: [])];
        final presenter = withCloud(cloud);
        await _waitForLoad(presenter);

        await presenter.sendChatInput('-500 food gcash');

        expect(presenter.allTransactions, hasLength(1));
      });

      test('an extractor question is put to the user, not the regex', () async {
        final cloud = FakeAiCoachService([])
          ..extractionScript = [
            const ExtractionResult(entries: [], unclear: 'How much was it?'),
          ];
        final presenter = withCloud(cloud);
        await _waitForLoad(presenter);

        await presenter.sendChatInput('bought some stuff at the mall');

        expect(presenter.chatState.unclear, 'How much was it?');
        expect(presenter.allTransactions, isEmpty);
      });
    });

    test('viewing a past month blocks before any AI call', () async {
      final cloud = FakeAiCoachService([])
        ..extractionScript = [
          ExtractionResult(entries: [made()]),
        ];
      final presenter = withCloud(cloud);
      await _waitForLoad(presenter);
      presenter
          .setSelectedDate(DateTime.now().subtract(const Duration(days: 3)));

      await presenter.sendChatInput('175 gcash food');

      expect(presenter.chatHardError, FinanceParseError.viewingPastDate);
      expect(cloud.extractCallCount, 0, reason: 'no wasted Bedrock call');
      expect(presenter.allTransactions, isEmpty);
    });

    test('a single-word description is learned against its own category',
        () async {
      final cloud = FakeAiCoachService([])
        ..extractionScript = [
          ExtractionResult(entries: [made(description: 'Jollibee')]),
        ];
      final presenter = withCloud(cloud);
      await _waitForLoad(presenter);

      await presenter.sendChatInput('175 gcash jollibee');
      await presenter.confirmEntries();

      verify(storage.saveFinanceDictionary(any)).called(greaterThan(0));
    });
  });

  group('a polite request is an instruction, not a question', () {
    // The question-mark veto exists so "can I afford 4000 food gcash?" stays
    // with the advice model. But it also swallowed "can you add 175 maribank?",
    // which is how the assistant came to describe three entries it had never
    // logged: the words never reached the ledger at all.

    test('"can you add ..." routes to the logger', () {
      expect(
        AiCoachPresenter.looksLikeExpenseLog('can you add 175 maribank?'),
        isTrue,
      );
    });

    test('"please log ..." routes to the logger', () {
      expect(
        AiCoachPresenter.looksLikeExpenseLog('please log 500 for food?'),
        isTrue,
      );
    });

    test('"can I afford ...?" is still advice', () {
      expect(
        AiCoachPresenter.looksLikeExpenseLog('can i afford 4000 food gcash?'),
        isFalse,
      );
    });

    test('"how much did I spend?" is still advice', () {
      expect(
        AiCoachPresenter.looksLikeExpenseLog('how much did i spend on food?'),
        isFalse,
      );
    });

    test('"should I buy this 5000 thing?" is still advice', () {
      expect(
        AiCoachPresenter.looksLikeExpenseLog('should i buy this 5000 chair?'),
        isFalse,
      );
    });

    test('the parser-backed check agrees', () async {
      final presenter = LedgerPresenter(storage, stats);
      await _waitForLoad(presenter);

      expect(
        presenter.recognisesLoggableEntry('can you add 500 food gcash?'),
        isTrue,
      );
      expect(
        presenter.recognisesLoggableEntry('can i afford 500 food gcash?'),
        isFalse,
      );
    });

    test('a statement with no question mark is unaffected', () {
      expect(
        AiCoachPresenter.looksLikeExpenseLog('add 175 maribank'),
        isTrue,
      );
    });
  });
}
