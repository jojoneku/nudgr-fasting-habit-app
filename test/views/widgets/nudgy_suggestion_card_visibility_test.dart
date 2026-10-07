import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/widgets/advisor_log_card.dart';
import 'package:intermittent_fasting/views/widgets/ai_chat_sheet.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

/// A tool executor with a card already waiting, the way the real one sits
/// while the user is looking at a suggestion.
class _WaitingHost extends ChangeNotifier
    implements FinanceToolExecutor, FinanceProposalHost {
  _WaitingHost(this._pending);

  PendingFinanceAction? _pending;

  @override
  PendingFinanceAction? get pending => _pending;

  @override
  Future<void> confirm({bool applyToFuture = false}) async {
    _pending = null;
    notifyListeners();
  }

  @override
  void decline() {
    _pending = null;
    notifyListeners();
  }

  @override
  Future<AiToolResult> runRead(AiToolCall call) async =>
      AiToolResult(toolUseId: call.id, ok: true, summary: '');

  @override
  Future<AiToolResult> propose(AiToolCall call) async =>
      AiToolResult(toolUseId: call.id, ok: true, summary: '');
}

/// The tallest card Nudgy makes: an installment with interest, nine rows.
PendingFinanceAction _installment() => const PendingFinanceAction(
      call: AiToolCall(id: 'tu_9', name: 'addInstallment', input: {}),
      title: 'Add installment: iPhone, ₱72,000 (24 mo)',
      isRecurring: false,
      details: [
        (label: 'Total amount', value: '₱72,000'),
        (label: 'Duration', value: '24 months'),
        (label: 'Monthly payment', value: '₱3,456.12'),
        (label: 'Interest rate', value: '1.5% / mo'),
        (label: 'Total interest', value: '₱10,946.88'),
        (label: 'Total payable', value: '₱82,946.88'),
        (label: 'Account', value: 'BPI Credit Card'),
        (label: 'Category', value: 'Gadgets'),
        (label: 'Date', value: '2026-10-07'),
      ],
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  });

  Future<LedgerPresenter> loadedLedger(WidgetTester tester) async {
    late LedgerPresenter ledger;
    await tester.runAsync(() async {
      ledger = LedgerPresenter(storage, stats);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    return ledger;
  }

  // The ledger's error card used to outrank everything on this strip. An
  // error from an earlier message — or from the hub's quick-log bar, which
  // shares the ledger — sat on top of a fresh suggestion, the card never
  // appeared, and the turn waited on an answer the user could not give.
  testWidgets('a waiting suggestion is shown over an earlier ledger error',
      (tester) async {
    final ledger = await loadedLedger(tester);
    await tester.runAsync(() async {
      ledger.setSelectedDate(DateTime.now().subtract(const Duration(days: 2)));
      await ledger.sendChatInput('coffee 120');
    });
    expect(ledger.chatHardError, FinanceParseError.viewingPastDate);

    final host = _WaitingHost(_installment());
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdvisorLogCard(ledger: ledger, proposals: host),
        ),
      ),
    ));

    expect(find.text('NUDGY SUGGESTS'), findsOneWidget);
    expect(find.text('Add it'), findsOneWidget);
  });

  // The proposal card sits in the chat's fixed, non-scrolling tail and had no
  // ceiling of its own. At the sheet's smallest drag position its nine rows
  // pushed "Add it" out of the sheet. The review card was given a ceiling for
  // exactly this; the suggestion card never was.
  testWidgets('the tallest suggestion keeps its buttons inside a short sheet',
      (tester) async {
    final ledger = await loadedLedger(tester);
    final cloud = MockAiCoachService();
    when(cloud.isAvailable).thenReturn(true);
    when(cloud.tier).thenReturn(AiCoachTier.cloud);
    when(cloud.downloadProgress).thenReturn(null);

    final presenter = AiCoachPresenter(
      stats: stats,
      service: cloud,
      ledger: ledger,
      toolExecutor: _WaitingHost(_installment()),
    );
    presenter.openSession(AiCoachEntryPoint.financeAdvisor);

    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 341,
            child: AiChatBody(
              presenter: presenter,
              entryPoint: AiCoachEntryPoint.financeAdvisor,
              showDragHandle: true,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Add it'), findsOneWidget);
    final button = tester.getRect(find.text('Add it'));
    expect(button.bottom, lessThanOrEqualTo(852.0));
    expect(button.top, greaterThanOrEqualTo(852.0 - 341));
  });
}
