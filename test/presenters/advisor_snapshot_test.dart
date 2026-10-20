import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/image_compressor.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';

class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

FinancialAccount _account(
  String id,
  String name,
  AccountCategory category,
  double balance, {
  String? parentAccountId,
  String? linkedAccountId,
  int? statementDay,
  int? paymentDueDay,
}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'bank',
      parentAccountId: parentAccountId,
      linkedAccountId: linkedAccountId,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
    );

/// The snapshot as Nudgy reads it, built from real treasury state.
///
/// The text tests in `ai_coach_context_advisor_test.dart` prove each line
/// renders; this proves `_buildContext` actually fills the fields — the gap
/// that left the statement balance out was never in the rendering.
void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockFastingPresenter fasting;
  late MockAiCoachService service;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    fasting = MockFastingPresenter();
    service = MockAiCoachService();
    when(stats.stats).thenReturn(UserStats.initial());
    when(fasting.isFasting).thenReturn(false);
    when(fasting.fastingGoalHours).thenReturn(16);
    when(service.isAvailable).thenReturn(true);
    when(service.tier).thenReturn(AiCoachTier.cloud);
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
    )).thenAnswer((_) => advisorStreamOf(const AdvisorReply(text: 'ok')));

    final now = DateTime.now();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          _account('bpi', 'BPI', AccountCategory.bank, 20000),
          _account('mom', 'Mom', AccountCategory.custodian, 5000,
              linkedAccountId: 'bpi'),
          _account('cc', 'BPI Credit Card', AccountCategory.creditCard, 9575,
              statementDay: 20, paymentDueDay: 5),
          _account('maya', 'Maya Savings', AccountCategory.savings, 30000),
          _account('mp2', 'MP2', AccountCategory.investment, 60000),
          _account('emer', 'Emergency', AccountCategory.savings, 10000,
              parentAccountId: 'maya'),
        ]);
    when(storage.loadBills()).thenAnswer((_) async => [
          // Filed under next month, as the generator files it — the month
          // the snapshot's bill list never looked at.
          Bill(
            id: 's1',
            name: 'BPI Credit Card statement',
            billType: BillType.creditCard,
            amount: 6200,
            dueDay: 5,
            month: toMonthKey(DateTime(now.year, now.month + 1)),
            categoryId: '',
            accountId: 'cc',
            paymentNote: Bill.autoStatementNote,
          ),
          Bill(
            id: 'b1',
            name: 'Internet',
            billType: BillType.utility,
            amount: 1699,
            dueDay: 28,
            month: toMonthKey(now),
            categoryId: '',
            accountId: 'bpi',
            paymentNote: 'Acct 1234',
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});

    final gifts = FinanceCategory(
      id: 'gifts',
      name: 'Gifts',
      type: CategoryType.expense,
      icon: 'gift',
      colorHex: '#FFFFFF',
    );
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [gifts]);
    // Budgeted, with nothing spent on it yet.
    when(storage.loadBudgets()).thenAnswer((_) async => [
          Budget(
            id: 'bg',
            categoryId: 'gifts',
            month: toMonthKey(now),
            allocatedAmount: 2000,
            group: 'wants',
            budgetType: BudgetType.monthly,
          ),
        ]);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
  });

  Future<String> snapshot() async {
    final treasury = TreasuryDashboardPresenter(storage);
    await treasury.load();
    final budget =
        BudgetPresenter(storage, stats, null, MockNotificationService());
    await budget.load();
    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      treasury: treasury,
      budget: budget,
      imageCompressor: _PassthroughCompressor(),
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    await p.send('what do I pay on my cards?');
    final ctx = verify(service.adviseFinance(
      messages: anyNamed('messages'),
      context: captureAnyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
    )).captured.first as AiCoachContext;
    p.dispose();
    return ctx.financeSnapshotSummary();
  }

  test('a statement filed for next month reaches the credit line', () async {
    final s = await snapshot();
    expect(s, contains('Statement balance: ₱6,200'));
    expect(s, contains('₱0 paid, ₱6,200 left'));
    // 9,575 owed less the 6,200 statement.
    expect(s, contains('₱3,375 charged after it closed'));
  });

  test('accounts, held money and pockets are itemised', () async {
    final s = await snapshot();
    expect(s, contains('BPI: ₱20,000 (₱5,000 of it held for someone else)'));
    expect(s, contains('Mom: ₱5,000 (inside BPI)'));
    expect(s, contains('Maya Savings: ₱30,000'));
    expect(s, contains('MP2: ₱60,000'));
    expect(s, contains('Emergency: ₱10,000 (inside Maya Savings)'));
  });

  test('bills carry where to pay from; a budget with no spend shows', () async {
    final s = await snapshot();
    expect(s, contains('Internet: ₱1,699'));
    expect(s, contains('pay from BPI; note: Acct 1234'));
    expect(s, contains('Gifts: ₱0 of ₱2,000 target'));
  });
}
