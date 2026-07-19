import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

// ─── Local builders ───────────────────────────────────────────────────────────

Bill _bill({
  required String id,
  double amount = 100,
  bool isPaid = false,
  String month = '2026-03',
  int dueDay = 10,
}) =>
    Bill(
      id: id,
      name: 'Bill $id',
      billType: BillType.utility,
      amount: amount,
      dueDay: dueDay,
      month: month,
      categoryId: '',
      isPaid: isPaid,
    );

Receivable _receivable({
  required String id,
  double amount = 200,
  bool isReceived = false,
  String month = '2026-03',
  DateTime? expectedDate,
}) =>
    Receivable(
      id: id,
      name: 'Receivable $id',
      receivableType: ReceivableType.salary,
      amount: amount,
      expectedDate: expectedDate,
      month: month,
      categoryId: '',
      isReceived: isReceived,
    );

BudgetedExpense _budgeted({
  required String id,
  double amount = 400,
  bool isPaid = false,
  String month = '2026-03',
}) =>
    BudgetedExpense(
      id: id,
      name: 'Budgeted $id',
      budgetedType: SetAsideType.savings,
      month: month,
      allocatedAmount: amount,
      categoryId: '',
      isPaid: isPaid,
    );

Installment _installment({
  required String id,
  double monthly = 500,
  String startMonth = '2026-01',
  int totalMonths = 6,
}) =>
    Installment(
      id: id,
      name: 'Installment $id',
      accountId: 'gcash',
      totalAmount: monthly * totalMonths,
      monthlyAmount: monthly,
      totalMonths: totalMonths,
      startMonth: startMonth,
    );

Future<void> _waitForLoad(LedgerPresenter ledger) async {
  while (ledger.isLoading) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late MockStorageService mockStorage;
  late MockStatsPresenter mockStats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late InstallmentPresenter installments;

  setUp(() {
    mockStorage = MockStorageService();
    mockStats = MockStatsPresenter();
    when(mockStorage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
    when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(mockStorage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(mockStorage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(mockStorage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(mockStorage.loadBills()).thenAnswer((_) async => []);
    when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(mockStorage.loadInstallments()).thenAnswer((_) async => []);
    when(mockStorage.saveBills(any)).thenAnswer((_) async {});
    when(mockStorage.saveReceivables(any)).thenAnswer((_) async {});
    when(mockStorage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(mockStorage.saveInstallments(any)).thenAnswer((_) async {});
    when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
    when(mockStorage.saveTransactions(any)).thenAnswer((_) async {});
    when(mockStorage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(mockStorage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.stats).thenReturn(UserStats.initial());

    ledger = LedgerPresenter(mockStorage, mockStats);
    presenter = BillsReceivablesPresenter(mockStorage, ledger, mockStats);
    installments = InstallmentPresenter(mockStorage, ledger, mockStats);
  });

  group('imminentUnpaidBills', () {
    test('includes due-soon unpaid bills soonest-first, excludes paid',
        () async {
      final month = toMonthKey(DateTime.now());
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'a', month: month, dueDay: 1),
            _bill(id: 'b', month: month, dueDay: 2),
            _bill(id: 'p', month: month, dueDay: 1, isPaid: true),
          ]);
      await presenter.load();
      await presenter.setMonth(month);

      // dueDay 1 and 2 are always overdue-or-within-a-few-days of today, so both
      // are imminent; the paid one is excluded; order is soonest-first.
      expect(presenter.imminentUnpaidBills.map((b) => b.id), ['a', 'b']);
    });

    test('excludes bills far in the future', () async {
      final now = DateTime.now();
      final future = toMonthKey(DateTime(now.year, now.month + 3));
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'far', month: future, dueDay: 15),
          ]);
      await presenter.load();
      await presenter.setMonth(future);

      expect(presenter.imminentUnpaidBills, isEmpty);
    });
  });

  group('comingUpItems', () {
    test('merges all four types, dates ascending then undated, inflow flagged',
        () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', dueDay: 10, amount: 100),
            _bill(id: 'b2', dueDay: 5, amount: 200),
            _bill(id: 'p', dueDay: 1, isPaid: true), // excluded
          ]);
      when(mockStorage.loadReceivables()).thenAnswer((_) async => [
            _receivable(
                id: 'r1', amount: 300, expectedDate: DateTime(2026, 3, 20)),
          ]);
      when(mockStorage.loadBudgetedExpenses())
          .thenAnswer((_) async => [_budgeted(id: 'e1', amount: 400)]);
      when(mockStorage.loadInstallments())
          .thenAnswer((_) async => [_installment(id: 'i1', monthly: 500)]);

      await presenter.load();
      await presenter.setMonth('2026-03');
      await installments.load();
      installments.setMonth('2026-03');
      await _waitForLoad(ledger);

      final items = presenter.comingUpItems(installments);

      expect(items.map((i) => i.name), [
        'Bill b2', // 2026-03-05
        'Bill b1', // 2026-03-10
        'Receivable r1', // 2026-03-20
        'Budgeted e1', // undated
        'Installment i1', // undated
      ]);
      // Only the receivable is an inflow.
      expect(
          items.where((i) => i.isInflow).map((i) => i.name), ['Receivable r1']);
      expect(items.firstWhere((i) => i.kind == ComingUpKind.installment).amount,
          500);
      expect(
          items.firstWhere((i) => i.kind == ComingUpKind.budgeted).amount, 400);
    });

    test('caps at 5, dropping undated items when dated ones fill the list',
        () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', dueDay: 10),
            _bill(id: 'b2', dueDay: 5),
            _bill(id: 'b3', dueDay: 25),
            _bill(id: 'b4', dueDay: 28),
            _bill(id: 'b5', dueDay: 15),
          ]);
      when(mockStorage.loadBudgetedExpenses())
          .thenAnswer((_) async => [_budgeted(id: 'e1')]);
      when(mockStorage.loadInstallments())
          .thenAnswer((_) async => [_installment(id: 'i1')]);

      await presenter.load();
      await presenter.setMonth('2026-03');
      await installments.load();
      installments.setMonth('2026-03');
      await _waitForLoad(ledger);

      final items = presenter.comingUpItems(installments);

      expect(items.length, 5);
      expect(items.every((i) => i.kind == ComingUpKind.bill), isTrue);
      expect(items.map((i) => i.name),
          ['Bill b2', 'Bill b1', 'Bill b5', 'Bill b3', 'Bill b4']);
    });

    test('a receivable with no expected date sorts after dated items',
        () async {
      when(mockStorage.loadBills())
          .thenAnswer((_) async => [_bill(id: 'b1', dueDay: 10)]);
      when(mockStorage.loadReceivables()).thenAnswer((_) async => [
            _receivable(id: 'asap', expectedDate: null),
          ]);

      await presenter.load();
      await presenter.setMonth('2026-03');
      await installments.load();
      installments.setMonth('2026-03');

      final items = presenter.comingUpItems(installments);
      expect(items.map((i) => i.name), ['Bill b1', 'Receivable asap']);
      expect(items.last.dateLabel, 'ASAP · incoming');
    });

    test('is empty when nothing is unpaid/unreceived', () async {
      await presenter.load();
      await presenter.setMonth('2026-03');
      await installments.load();
      installments.setMonth('2026-03');

      expect(presenter.comingUpItems(installments), isEmpty);
    });
  });

  group('per-bill reminder', () {
    test('addBill persists the reminder lead time', () async {
      await presenter.load();
      await presenter.setMonth('2026-03');
      await presenter.addBill(Bill(
        id: 'r1',
        name: 'Internet',
        billType: BillType.utility,
        amount: 100,
        dueDay: 10,
        month: '2026-03',
        categoryId: '',
        reminderDaysBefore: 2,
      ));

      final saved =
          verify(mockStorage.saveBills(captureAny)).captured.last as List<Bill>;
      expect(saved.firstWhere((b) => b.id == 'r1').reminderDaysBefore, 2);
    });
  });
}
