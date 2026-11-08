import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

/// The Bills tab groups (Plan 071 Phase 6): the hero bill, the due-soon and
/// later groups, paid bills, set-aside totals, tab counts, and the shared
/// summary and credit-card lines. "Today" is pinned to 10 March 2026.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const month = '2026-03';
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late InstallmentPresenter installments;

  Bill bill(String id, int dueDay, {bool paid = false, double amount = 100}) =>
      Bill(
        id: id,
        name: id,
        billType: BillType.utility,
        amount: amount,
        dueDay: dueDay,
        month: month,
        categoryId: '',
        isPaid: paid,
        paidAmount: paid ? amount : null,
      );

  BudgetedExpense setAside(String id, double amount, {bool paid = false}) =>
      BudgetedExpense(
        id: id,
        name: id,
        budgetedType: SetAsideType.savings,
        month: month,
        allocatedAmount: amount,
        categoryId: '',
        isPaid: paid,
      );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => [
          bill('later-28', 28),
          bill('soon-12', 12),
          bill('hero-5', 5),
          bill('later-25', 25),
          bill('soon-15', 15),
          bill('paid-3', 3, paid: true),
        ]);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => [
          setAside('fund-a', 1000),
          setAside('fund-b', 500),
          setAside('fund-done', 300, paid: true),
        ]);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadDismissedStatementKeys())
        .thenAnswer((_) async => <String>{});
    when(storage.saveDismissedStatementKeys(any)).thenAnswer((_) async {});
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.saveInstallments(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
    presenter = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: MockNotificationService(),
      clock: () => DateTime(2026, 3, 10),
    );
  });

  Future<void> loaded() async {
    await presenter.load();
    await installments.load();
    await presenter.setMonth(month);
    installments.setMonth(month);
  }

  test('the hero is the most overdue unpaid bill', () async {
    await loaded();
    expect(presenter.heroBill?.id, 'hero-5');
  });

  test('due soon is the overdue and coming week, the hero first', () async {
    await loaded();
    // The hero bill stays in "Due soon" so its row actions (Mark unpaid,
    // items, delete, batch select) are reachable; the hero card has only
    // Mark paid and Edit.
    expect(presenter.unpaidDueSoon.map((b) => b.id),
        ['hero-5', 'soon-12', 'soon-15']);
    expect(presenter.unpaidDueSoon.first.id, presenter.heroBill!.id);
  });

  test('later is the unpaid bills more than a week out, by due day', () async {
    await loaded();
    expect(presenter.unpaidLater.map((b) => b.id), ['later-25', 'later-28']);
  });

  test('every bill is in exactly one list', () async {
    await loaded();
    final places = [
      ...presenter.unpaidDueSoon.map((b) => b.id),
      ...presenter.unpaidLater.map((b) => b.id),
      ...presenter.paidBills.map((b) => b.id),
    ];
    expect(places.toSet().length, places.length, reason: 'no duplicates');
    expect(places.toSet(), presenter.bills.map((b) => b.id).toSet());
  });

  test('paid bills holds only paid bills', () async {
    await loaded();
    expect(presenter.paidBills.map((b) => b.id), ['paid-3']);
    expect(presenter.paidBills.every((b) => b.isPaid), isTrue);
  });

  test('unpaid bills lists the due-soon ones, hero included, then later',
      () async {
    await loaded();
    expect(presenter.unpaidBills.map((b) => b.id),
        ['hero-5', 'soon-12', 'soon-15', 'later-25', 'later-28']);
  });

  test('set-aside totals count only the unfunded ones', () async {
    await loaded();
    expect(presenter.setAsidePendingTotal, 1500);
    expect(presenter.setAsidePendingCount, 2);
  });

  test('each tab count is the length of the list that tab shows', () async {
    await loaded();
    final counts = presenter.tabCounts(installments);
    expect(counts.upcoming,
        presenter.unpaidDueSoon.length + presenter.unpaidLater.length);
    expect(counts.upcoming, presenter.unpaidBills.length);
    expect(counts.upcoming, 5, reason: 'the hero bill is counted');
    expect(counts.setAsides, presenter.budgetedExpenses.length);
    expect(counts.receivables, presenter.receivables.length);
    expect(counts.installments, installments.dueThisMonth.length);
    expect(counts.paid, presenter.paidBills.length);
  });

  test('a lone hero bill is still an Upcoming row', () async {
    when(storage.loadBills()).thenAnswer((_) async => [bill('only', 5)]);
    await loaded();
    expect(presenter.heroBill?.id, 'only');
    expect(presenter.unpaidDueSoon.map((b) => b.id), ['only']);
    expect(presenter.tabCounts(installments).upcoming, 1);
  });

  test('an empty Upcoming means nothing is due', () async {
    when(storage.loadBills())
        .thenAnswer((_) async => [bill('done', 5, paid: true)]);
    await loaded();
    expect(presenter.heroBill, isNull);
    expect(presenter.tabCounts(installments).upcoming, 0);
    expect(
        presenter.upcomingEmptyMessage, 'No bills due. You are all caught up.');
  });

  test('the summary lines carry the presenter totals', () async {
    await loaded();
    final lines = {
      for (final l in presenter.monthSummaryLines(installments)) l.label: l
    };
    expect(lines['Pending']!.value, formatPeso(presenter.totalBillsPending));
    expect(lines['Pending']!.sub, '5 unpaid');
    expect(lines['Paid']!.value, formatPeso(presenter.totalBillsPaid));
    expect(lines['Set-asides to fund']!.value, formatPeso(1500));
    expect(lines['Set-asides to fund']!.tone, BillsSummaryTone.warning);
    expect(lines['To receive']!.value, '+${formatPeso(0)}');
  });

  test('credit lines: owed, available and the per-card line', () async {
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'bpi-cc',
            name: 'BPI Card',
            category: AccountCategory.creditCard,
            balance: 4000,
            creditLimit: 10000,
            statementDay: 20,
            paymentDueDay: 5,
            colorHex: '#FF0000',
            icon: 'card',
          ),
          FinancialAccount(
            id: 'maya-cc',
            name: 'Maya Card',
            category: AccountCategory.creditCard,
            balance: 0,
            creditLimit: 5000,
            colorHex: '#00FF00',
            icon: 'card',
          ),
        ]);
    await ledger.load();
    await loaded();

    expect(presenter.creditAccountsWithBalance.map((c) => c.id), ['bpi-cc']);
    final bpi = presenter.creditAccounts.firstWhere((c) => c.id == 'bpi-cc');
    final available = presenter.creditAccounts
        .fold<double>(0, (s, c) => s + (c.availableCredit ?? 0));
    expect(presenter.totalCreditAvailable, available);
    expect(
        presenter.creditLinesDescription,
        startsWith(
            'Owe ${formatPeso(bpi.currentPayable)} across 1 of 2 lines'));
    expect(presenter.creditLineSubtitle(bpi), contains('statement 20th'));
    expect(presenter.creditLineSubtitle(bpi), contains('due 5th'));
  });

  test(
      'credit lines: unbilled installments are named apart, never as owed '
      'now', () async {
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'bpi-cc',
            name: 'BPI Card',
            category: AccountCategory.creditCard,
            balance: 0,
            creditLimit: 50000,
            colorHex: '#FF0000',
            icon: 'card',
          ),
        ]);
    when(storage.loadInstallments()).thenAnswer((_) async => [
          Installment(
            id: 'laptop',
            name: 'Laptop',
            accountId: 'bpi-cc',
            totalAmount: 12000,
            monthlyAmount: 1000,
            totalMonths: 12,
            startMonth: '2026-04',
          ),
        ]);
    await ledger.load();
    await loaded();

    final card = presenter.creditAccounts.single;
    expect(card.unbilledInstallments, 12000, reason: 'the live hold');
    // Nothing is on a statement, so no row and the empty state shows.
    expect(presenter.creditAccountsWithBalance, isEmpty);
    expect(presenter.creditOwedNow, 0);
    expect(presenter.creditUnbilledInstallments, 12000);

    final line = presenter.creditLinesDescription;
    expect(line, isNot(contains('Owe ')));
    expect(line, startsWith('Nothing owed now'));
    expect(
        line, contains('${formatPeso(12000)} in installments not yet billed'));
    expect(line, contains('${formatPeso(38000)} available'));
  });

  test('credit lines: an over-limit card does not cancel another card\'s room',
      () async {
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'over',
            name: 'Over Card',
            category: AccountCategory.creditCard,
            balance: 12000,
            creditLimit: 10000,
            colorHex: '#FF0000',
            icon: 'card',
          ),
          FinancialAccount(
            id: 'room',
            name: 'Room Card',
            category: AccountCategory.creditCard,
            balance: 1000,
            creditLimit: 5000,
            colorHex: '#00FF00',
            icon: 'card',
          ),
        ]);
    await ledger.load();
    await loaded();

    // 0 (over its limit, not -2,000) + 4,000.
    expect(presenter.totalCreditAvailable, 4000);
    expect(presenter.creditOwedNow, 13000);
    expect(
        presenter.creditLinesDescription,
        'Owe ${formatPeso(13000)} across 2 of 2 lines · '
        '${formatPeso(4000)} available · pay anytime');
  });
}
