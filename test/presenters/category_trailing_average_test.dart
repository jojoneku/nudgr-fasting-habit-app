import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

/// The per-category baseline the advisor compares this month against.
///
/// Without it every category over budget reads identically. "Food is ₱5,240
/// against a ₱3,900 three-month average" is a different conversation from "Food
/// is ₱5,240, same as always, the budget is simply wrong" — and the model is
/// told never to compute a figure the snapshot does not contain, so the baseline
/// has to be handed to it.
void main() {
  final thisMonth = toMonthKey(DateTime.now());
  final m1 = previousMonth(thisMonth);
  final m2 = previousMonth(m1);
  final m3 = previousMonth(m2);

  late MockStorageService storage;

  FinanceCategory cat(String id) => FinanceCategory(
        id: id,
        name: id,
        type: CategoryType.expense,
        icon: 'tag',
        colorHex: '#fff',
      );

  TransactionRecord spend({
    required String id,
    required String month,
    required String categoryId,
    required double amount,
  }) =>
      TransactionRecord(
        id: id,
        date: DateTime.parse('$month-10'),
        accountId: 'acc',
        categoryId: categoryId,
        amount: amount,
        type: TransactionType.outflow,
        description: id,
        month: month,
      );

  Future<TreasuryDashboardPresenter> load(
      List<TransactionRecord> txns, List<FinanceCategory> cats) async {
    storage = MockStorageService();
    when(storage.loadAccounts()).thenAnswer((_) async => <FinancialAccount>[
          FinancialAccount(
            id: 'acc',
            name: 'Cash',
            category: AccountCategory.cash,
            balance: 10000,
            colorHex: '#fff',
            icon: 'wallet',
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => txns);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => cats);
    when(storage.loadBudgets()).thenAnswer((_) async => []);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    final p = TreasuryDashboardPresenter(storage);
    await p.load();
    return p;
  }

  test('averages the three months before this one, not including it', () async {
    final p = await load([
      spend(id: 'a', month: m1, categoryId: 'food', amount: 3000),
      spend(id: 'b', month: m2, categoryId: 'food', amount: 4000),
      spend(id: 'c', month: m3, categoryId: 'food', amount: 5000),
      // This month is the thing being judged — folding it in would drag the
      // baseline toward whatever is being compared against it.
      spend(id: 'd', month: thisMonth, categoryId: 'food', amount: 90000),
    ], [
      cat('food')
    ]);

    final r = p.categoryTrailingAverage(months: 3);
    expect(r.months, 3);
    expect(r.averages['food'], 4000);
  });

  test('a month with no spend still counts in the divisor', () async {
    final p = await load([
      spend(id: 'a', month: m1, categoryId: 'food', amount: 3000),
      spend(id: 'b', month: m3, categoryId: 'food', amount: 3000),
      // m2 has nothing. A category bought twice a year averages low, and that
      // is the honest reading — not "₱3,000 every month".
      spend(id: 'c', month: m2, categoryId: 'other', amount: 100),
    ], [
      cat('food'),
      cat('other')
    ]);

    final r = p.categoryTrailingAverage(months: 3);
    expect(r.months, 3);
    expect(r.averages['food'], 2000);
  });

  test('divides by the history that exists, not the window asked for',
      () async {
    // A ledger two months old must not report an average diluted by months
    // that could never have held anything.
    final p = await load([
      spend(id: 'a', month: m1, categoryId: 'food', amount: 3000),
      spend(id: 'b', month: m2, categoryId: 'food', amount: 3000),
    ], [
      cat('food')
    ]);

    final r = p.categoryTrailingAverage(months: 6);
    expect(r.months, 2);
    expect(r.averages['food'], 3000);
  });

  test('an empty ledger reports no baseline rather than zero', () async {
    final p = await load([], [cat('food')]);

    final r = p.categoryTrailingAverage();
    expect(r.months, 0);
    expect(r.averages, isEmpty);
  });

  test('transfers and excluded categories are left out', () async {
    final transfer = FinanceCategory.transfer();
    final p = await load([
      spend(id: 'a', month: m1, categoryId: 'food', amount: 1000),
      // A transfer leg is not spending, on any month.
      TransactionRecord(
        id: 'xfer',
        date: DateTime.parse('$m1-10'),
        accountId: 'acc',
        categoryId: transfer.id,
        amount: 50000,
        type: TransactionType.outflow,
        description: 'moved',
        month: m1,
        transferGroupId: 'g1',
      ),
    ], [
      cat('food'),
      transfer
    ]);

    final r = p.categoryTrailingAverage(months: 1);
    expect(r.averages['food'], 1000);
    expect(r.averages[transfer.id], isNull);
  });
}
