import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_conversation.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/extracted_entry.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/image_compressor.dart';
import 'package:intermittent_fasting/utils/finance_entry_extraction.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';

/// Every way a Nudgy suggestion card used to fail to appear, one test each.
///
/// "Sometimes the card doesn't show" turned out to be several unrelated
/// faults, and none of them was in the card itself: the request never reached
/// Nudgy, the ledger answered with nothing, a stale error sat on top of the
/// card, or a reopened chat lost the turn the card belonged to.

class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

/// The ledger's cloud tier, reduced to the one call the advisor routing path
/// makes: the one-shot extractor. Anything else is a test bug and throws.
class _ExtractorOnly implements AiCoachService {
  _ExtractorOnly(this.result);

  final ExtractionResult? result;
  final List<String> messages = [];

  @override
  AiCoachTier get tier => AiCoachTier.cloud;

  @override
  bool get isAvailable => true;

  @override
  Future<ExtractionResult?> extractFinanceEntries({
    required String message,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required String Function(String categoryId) categoryNameFor,
    DateTime? now,
  }) async {
    messages.add(message);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A proposal host the test answers by hand, so a turn can be held open on a
/// pending card exactly as it is while the user is looking at one.
class _HeldExecutor implements FinanceToolExecutor {
  final List<String> proposals = [];
  Completer<AiToolResult>? _decision;

  bool get isWaiting => _decision != null;

  void confirm() {
    final d = _decision!;
    _decision = null;
    d.complete(const AiToolResult(toolUseId: 'tu_1', ok: true, summary: 'ok'));
  }

  @override
  Future<AiToolResult> runRead(AiToolCall call) async =>
      AiToolResult(toolUseId: call.id, ok: true, summary: 'none');

  @override
  Future<AiToolResult> propose(AiToolCall call) {
    proposals.add(call.name);
    _decision = Completer<AiToolResult>();
    return _decision!.future;
  }
}

FinancialAccount _acc(String id, String name) => FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.bank,
      balance: 1000,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name) => FinanceCategory(
      id: id,
      name: name,
      type: CategoryType.expense,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

AdvisorReply _toolTurn(String name, {String text = ''}) => AdvisorReply(
      text: text,
      toolCalls: [AiToolCall(id: 'tu_1', name: name, input: const {})],
      assistantContent: [
        {'type': 'tool_use', 'id': 'tu_1', 'name': name, 'input': {}}
      ],
    );

ExtractedEntry _entry(double amount, String description) => ExtractedEntry(
      txn: ParsedTransaction(
        amount: amount,
        type: TransactionType.outflow,
        accountId: 'bpi',
        categoryId: 'food',
        description: description,
        descriptionIsClean: true,
      ),
    );

void main() {
  late MockStatsPresenter stats;
  late MockFastingPresenter fasting;
  late MockAiCoachService advisor;
  late MockStorageService storage;

  setUp(() {
    stats = MockStatsPresenter();
    fasting = MockFastingPresenter();
    advisor = MockAiCoachService();
    storage = MockStorageService();
    when(stats.stats).thenReturn(UserStats.initial());
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(fasting.isFasting).thenReturn(false);
    when(fasting.fastingGoalHours).thenReturn(16);
    when(advisor.isAvailable).thenReturn(true);
    when(advisor.tier).thenReturn(AiCoachTier.cloud);

    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [_acc('bpi', 'BPI')]);
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => [_cat('food', 'Food')]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
  });

  /// Answers each successive advisor hop from [script], repeating the last.
  void scriptAdvisor(List<AdvisorReply> script) {
    var i = 0;
    when(advisor.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
    )).thenAnswer((_) {
      final reply = script[i < script.length ? i : script.length - 1];
      i++;
      return advisorStreamOf(reply);
    });
  }

  int advisorHops() => verify(advisor.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        tools: anyNamed('tools'),
      )).callCount;

  Future<LedgerPresenter> ledgerWith(_ExtractorOnly cloud) async {
    final ledger = LedgerPresenter(storage, stats, cloudAi: cloud);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return ledger;
  }

  AiCoachPresenter advisorWith({
    LedgerPresenter? ledger,
    FinanceToolExecutor? executor,
    MockStorageService? store,
  }) {
    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: advisor,
      imageCompressor: _PassthroughCompressor(),
      ledger: ledger,
      toolExecutor: executor,
      storage: store,
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    return p;
  }

  group('requests only Nudgy can carry out reach Nudgy', () {
    // The advisor routes anything that looks like a spend log to the ledger's
    // transaction pipeline before Nudgy sees it. "Add", "pay" and "bill" are
    // spend verbs there — so "add an installment …" became a ₱24,000 expense
    // card (or an error, or nothing), and Nudgy's addInstallment card could
    // never appear for the very sentence that asks for it.
    test('an installment request goes to Nudgy, not the expense pipeline',
        () async {
      final cloud = _ExtractorOnly(ExtractionResult(entries: [
        _entry(24000, 'Phone'),
      ]));
      final ledger = await ledgerWith(cloud);
      final executor = _HeldExecutor();
      scriptAdvisor([
        _toolTurn('addInstallment'),
        const AdvisorReply(text: 'Added.'),
      ]);
      final p = advisorWith(ledger: ledger, executor: executor);

      final sent =
          p.send('add an installment for my phone 24000 over 12 months on BPI');
      await pumpEventQueue();

      expect(cloud.messages, isEmpty,
          reason: 'the expense extractor must not swallow a tool request');
      expect(executor.proposals, ['addInstallment']);
      expect(ledger.chatState.entries, isEmpty);

      executor.confirm();
      await sent;
      expect(p.messages.last.text, 'Added.');
      p.dispose();
    });

    test('bills with a due day and set-asides are tool requests', () {
      for (final text in [
        'add an installment for my phone 24000 over 12 months on BPI',
        'bought a laptop 60000 on 0% for 12 months',
        'add my meralco bill 2500 due on the 15th',
        'set aside 3000 for braces',
        'add a receivable 1500 from Ana',
        'put 2000 in the sinking fund',
      ]) {
        expect(AiCoachPresenter.isAdvisorToolRequest(text), isTrue,
            reason: text);
      }
    });

    test('ordinary spend logs still go to the ledger', () {
      for (final text in [
        'coffee 120',
        'spent 500 on lunch gcash',
        'paid 2500 meralco bill from bpi',
        'log 175 grab',
      ]) {
        expect(AiCoachPresenter.isAdvisorToolRequest(text), isFalse,
            reason: text);
      }
    });

    test('without a tool executor the old routing is untouched', () async {
      final cloud = _ExtractorOnly(ExtractionResult(entries: [
        _entry(24000, 'Phone'),
      ]));
      final ledger = await ledgerWith(cloud);
      scriptAdvisor([const AdvisorReply(text: 'unused')]);
      final p = advisorWith(ledger: ledger);

      await p.send('add an installment for my phone 24000 on BPI');

      // Nothing could carry the tool out, so the ledger keeps the message.
      expect(cloud.messages, hasLength(1));
      p.dispose();
    });
  });

  group('a message the ledger cannot log is answered, not dropped', () {
    // The extractor answers "nothing to log here" with a question. That
    // question lives on LedgerChatState.unclear, which no chat surface
    // renders — so the user's message sat there with no reply, no card and no
    // error.
    test('the turn falls through to Nudgy', () async {
      final cloud = _ExtractorOnly(
          const ExtractionResult(unclear: 'What was the 500 for?'));
      final ledger = await ledgerWith(cloud);
      scriptAdvisor([const AdvisorReply(text: 'What was the ₱500 for?')]);
      final p = advisorWith(ledger: ledger, executor: _HeldExecutor());

      await p.send('paid 500');

      expect(cloud.messages, ['paid 500']);
      expect(advisorHops(), 1);
      expect(p.messages.map((m) => m.text).toList(),
          ['paid 500', 'What was the ₱500 for?']);
      expect(p.isResponding, isFalse);
      p.dispose();
    });

    test('a message the ledger did put on a card is not sent twice', () async {
      final cloud =
          _ExtractorOnly(ExtractionResult(entries: [_entry(500, 'Lunch')]));
      final ledger = await ledgerWith(cloud);
      scriptAdvisor([const AdvisorReply(text: 'unused')]);
      final p = advisorWith(ledger: ledger, executor: _HeldExecutor());

      await p.send('paid 500 lunch');

      expect(ledger.chatState.entries, hasLength(1));
      verifyNever(advisor.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        tools: anyNamed('tools'),
      ));
      p.dispose();
    });
  });

  group('the review card Nudgy fills', () {
    // A new set of rows supersedes an error left by an earlier message, the
    // same as every other path into the card. The error card outranks the
    // review card, so a stale one hid the rows Nudgy had just put there.
    test('clears an error left by an earlier message', () async {
      final ledger = await ledgerWith(_ExtractorOnly(null));
      ledger.setSelectedDate(DateTime.now().subtract(const Duration(days: 3)));
      await ledger.sendChatInput('coffee 120');
      expect(ledger.chatHardError, FinanceParseError.viewingPastDate);
      ledger.setSelectedDate(null);

      ledger.presentEntriesForReview([_entry(300, 'Lunch')]);

      expect(ledger.chatHardError, isNull);
      expect(ledger.chatState.entries, hasLength(1));
    });

    // One turn can call logTransactions more than once — the model is free
    // to emit parallel tool calls — and each call used to REPLACE the rows on
    // the card. The model was told every batch was waiting there; only the
    // last one was.
    test('keeps rows already on the card when more arrive', () async {
      final ledger = await ledgerWith(_ExtractorOnly(null));

      ledger.presentEntriesForReview([_entry(300, 'Lunch')]);
      ledger.presentEntriesForReview([_entry(120, 'Coffee')]);

      expect(ledger.chatState.entries.map((e) => e.txn.description),
          ['Lunch', 'Coffee']);
      expect(ledger.chatState.phase, ChatPhase.reviewing);
    });

    test('does not stack the same row twice', () async {
      final ledger = await ledgerWith(_ExtractorOnly(null));

      ledger.presentEntriesForReview([_entry(300, 'Lunch')]);
      ledger.presentEntriesForReview([_entry(300, 'Lunch')]);

      expect(ledger.chatState.entries, hasLength(1));
    });

    test('keeps two identical charges sent in one batch', () async {
      final ledger = await ledgerWith(_ExtractorOnly(null));

      ledger.presentEntriesForReview(
          [_entry(120, 'Coffee'), _entry(120, 'Coffee')]);

      expect(ledger.chatState.entries, hasLength(2));
    });
  });

  group('reopening the chat mid-turn', () {
    // Mobile re-runs openSession every time the sheet opens. Closing the sheet
    // while a card waits and opening it again reloaded the thread from storage
    // — which does not have the in-flight turn yet — so the prose that
    // introduced the card vanished, and the reply after the user answered the
    // card was written over whatever message happened to be last.
    test('keeps the live thread and the card it belongs to', () async {
      final saved = AdvisorConversation(
        id: 'c1',
        title: 'Earlier',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
        messages: [
          AiChatMessage.user('how am I doing?'),
          AiChatMessage.assistantStreaming()
              .copyWith(text: 'You are fine.', isStreaming: false),
        ],
      );
      final store = MockStorageService();
      when(store.loadAdvisorConversations()).thenAnswer((_) async => [saved]);
      when(store.loadAdvisorProfile()).thenAnswer((_) async => null);
      when(store.loadAdvisorHistory()).thenAnswer((_) async => []);
      when(store.saveAdvisorConversations(any)).thenAnswer((_) async {});
      when(store.saveAdvisorHistory(any)).thenAnswer((_) async {});

      final executor = _HeldExecutor();
      scriptAdvisor([
        _toolTurn('addSetAside', text: 'Setting that aside.'),
        const AdvisorReply(text: 'Done — ₱3,000 set aside.'),
      ]);
      final p = advisorWith(executor: executor, store: store);
      await pumpEventQueue();

      final sent = p.send('set aside 3000 for braces');
      await pumpEventQueue();
      expect(executor.isWaiting, isTrue);

      // The sheet is closed and opened again while the card is up.
      p.openSession(AiCoachEntryPoint.financeAdvisor);
      await pumpEventQueue();
      expect(
          p.messages.map((m) => m.text), contains('set aside 3000 for braces'));

      executor.confirm();
      await sent;

      expect(p.messages.map((m) => m.text).toList(), [
        'how am I doing?',
        'You are fine.',
        'set aside 3000 for braces',
        'Done — ₱3,000 set aside.',
      ]);
      p.dispose();
    });
  });
}
