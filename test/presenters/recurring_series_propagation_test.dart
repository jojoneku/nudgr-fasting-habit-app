import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// A 'YYYY-MM' key [delta] months from now (delta may be negative).
String _monthKey(int delta) {
  final now = DateTime.now();
  return toMonthKey(DateTime(now.year, now.month + delta));
}

/// [day] of the month [monthKey] names.
DateTime _dayIn(String monthKey, int day) {
  final parts = monthKey.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), day);
}

/// Recurring items are stored one row per month, seeded once and then frozen.
/// So raising your rent in August used to leave the September row — already
/// generated the moment you paged forward — sitting at the old figure forever,
/// with nothing on screen admitting it.
///
/// These tests pin the fix: a save can carry across the later months, it stops
/// at anything already settled, it never reaches backwards, and the rows it
/// finds are found by series rather than by name.
void main() {
  // Relative to today, not pinned to a calendar month. `aug` is the month the
  // app would open on, and [BillsReceivablesPresenter.load] seeds that month
  // from the recurring rows before it — so a fixture pinned to a literal
  // '2026-08' would start growing extra rows the moment the real calendar
  // moved past it, and these tests would rot on a date. The July→October
  // naming is kept for readability.
  final jul = _monthKey(-1);
  final aug = _monthKey(0);
  final sep = _monthKey(1);
  final oct = _monthKey(2);

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  late List<Bill> bills;
  late List<Receivable> receivables;
  late List<BudgetedExpense> expenses;

  Bill rent({
    required String id,
    required String month,
    double amount = 15000,
    String name = 'Rent',
    String? seriesId,
    bool isRecurring = true,
    bool isPaid = false,
    String? transactionId,
  }) =>
      Bill(
        id: id,
        name: name,
        billType: BillType.other,
        amount: amount,
        dueDay: 5,
        month: month,
        categoryId: 'home',
        isRecurring: isRecurring,
        recurrenceType: isRecurring ? RecurrenceType.monthly : null,
        seriesId: seriesId,
        isPaid: isPaid,
        transactionId: transactionId,
      );

  Receivable salary({
    required String id,
    required String month,
    double amount = 40000,
    String name = 'Salary',
    String? seriesId,
    bool isRecurring = true,
    bool isReceived = false,
  }) =>
      Receivable(
        id: id,
        name: name,
        receivableType: ReceivableType.salary,
        amount: amount,
        expectedDate: DateTime.parse('$month-15'),
        month: month,
        categoryId: 'pay',
        isRecurring: isRecurring,
        recurrenceType: isRecurring ? RecurrenceType.monthly : null,
        seriesId: seriesId,
        isReceived: isReceived,
      );

  BudgetedExpense fund({
    required String id,
    required String month,
    double allocated = 3000,
    String name = 'Braces Fund',
    String? seriesId,
    bool isRecurring = true,
    bool isPaid = false,
    double spent = 0,
  }) =>
      BudgetedExpense(
        id: id,
        name: name,
        budgetedType: SetAsideType.sinkingFund,
        month: month,
        allocatedAmount: allocated,
        categoryId: 'health',
        isRecurring: isRecurring,
        recurrenceType: isRecurring ? RecurrenceType.monthly : null,
        seriesId: seriesId,
        isPaid: isPaid,
        spentAmount: spent,
      );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    bills = <Bill>[];
    receivables = <Receivable>[];
    expenses = <BudgetedExpense>[];

    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'home',
            name: 'Home',
            type: CategoryType.expense,
            icon: 'tag',
            colorHex: '#FFFFFF',
          ),
        ]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});

    when(storage.loadBills()).thenAnswer((_) async => bills);
    when(storage.saveBills(any)).thenAnswer((inv) async {
      bills = List<Bill>.from(inv.positionalArguments.first as List<Bill>);
    });
    when(storage.loadReceivables()).thenAnswer((_) async => receivables);
    when(storage.saveReceivables(any)).thenAnswer((inv) async {
      receivables = List<Receivable>.from(
          inv.positionalArguments.first as List<Receivable>);
    });
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => expenses);
    when(storage.saveBudgetedExpenses(any)).thenAnswer((inv) async {
      expenses = List<BudgetedExpense>.from(
          inv.positionalArguments.first as List<BudgetedExpense>);
    });
  });

  // [month] defaults to `aug`, but not as a parameter default: the month keys
  // are relative to today, so they are no longer compile-time constants.
  Future<BillsReceivablesPresenter> load({String? month}) async {
    final ledger = LedgerPresenter(storage, stats);
    final presenter = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: notifications,
    );
    await presenter.load();
    await presenter.setMonth(month ?? aug);
    var guard = 0;
    while (ledger.isLoading && guard++ < 50) {
      await Future<void>.delayed(Duration.zero);
    }
    return presenter;
  }

  Bill billIn(BillsReceivablesPresenter p, String month) =>
      p.allBills.firstWhere((b) => b.month == month);

  group('editing a recurring bill', () {
    test('carries the new amount into months already generated ahead',
        () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
        rent(id: 'oct', month: oct, seriesId: 's1'),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(amount: 18000),
        applyToFuture: true,
      );

      expect(billIn(p, sep).amount, 18000,
          reason: 'the month that used to stay frozen at the seeded amount');
      expect(billIn(p, oct).amount, 18000,
          reason: 'every later month, not just the next one');
    });

    test('leaves the later months alone when scoped to this month', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      await p.updateBill(billIn(p, aug).copyWith(amount: 18000));

      expect(billIn(p, aug).amount, 18000);
      expect(billIn(p, sep).amount, 15000,
          reason: 'a one-off correction must not leak forward');
    });

    test('never reaches backwards into a month already closed', () async {
      bills = [
        rent(id: 'jul', month: jul, seriesId: 's1'),
        rent(id: 'aug', month: aug, seriesId: 's1'),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(amount: 18000),
        applyToFuture: true,
      );

      expect(billIn(p, jul).amount, 15000,
          reason: 'July is history — what you actually owed then does not '
              'change because September will cost more');
    });

    test('skips a future month that is already paid', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(
          id: 'sep',
          month: sep,
          seriesId: 's1',
          isPaid: true,
          transactionId: 'txn-1',
        ),
        rent(id: 'oct', month: oct, seriesId: 's1'),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(amount: 18000),
        applyToFuture: true,
      );

      expect(billIn(p, sep).amount, 15000,
          reason: 'that money already moved and the ledger says how much');
      expect(billIn(p, oct).amount, 18000,
          reason: 'a settled month in the middle does not stop the rest');
    });

    test('follows the series through a rename, which name-matching could not',
        () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(name: 'Apartment Rent', amount: 18000),
        applyToFuture: true,
      );

      expect(billIn(p, sep).name, 'Apartment Rent');
      expect(billIn(p, sep).amount, 18000);
    });

    test('does not touch a same-named bill from an unrelated series', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep-other', month: sep, seriesId: 's2'),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(amount: 18000),
        applyToFuture: true,
      );

      expect(billIn(p, sep).amount, 15000,
          reason: 'two bills can share a name without being the same bill');
    });

    test('carries the whole template, not just the amount', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(
          amount: 18000,
          dueDay: 20,
          categoryId: 'housing',
          billType: BillType.utility,
        ),
        applyToFuture: true,
      );

      final sepBill = billIn(p, sep);
      expect(sepBill.dueDay, 20);
      expect(sepBill.categoryId, 'housing');
      expect(sepBill.billType, BillType.utility);
    });

    test('switching recurrence off drops the months generated ahead', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
        rent(id: 'oct', month: oct, seriesId: 's1'),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(isRecurring: false),
        applyToFuture: true,
      );

      expect(p.allBills.map((b) => b.month), [aug],
          reason: 'a subscription you ended should not keep billing you');
    });

    test('switching recurrence off keeps a future month that is already paid',
        () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(
          id: 'sep',
          month: sep,
          seriesId: 's1',
          isPaid: true,
          transactionId: 'txn-1',
        ),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(isRecurring: false),
        applyToFuture: true,
      );

      expect(p.allBills.map((b) => b.id), containsAll(['aug', 'sep']),
          reason: 'deleting a paid row would orphan its ledger transaction');
    });
  });

  group('adding a recurring bill', () {
    test('reaches months that were already generated', () async {
      // September exists because the user paged forward once. The seeding pass
      // skips a month that already holds anything, so a bill added now would
      // otherwise never appear there.
      bills = [rent(id: 'sep-other', month: sep, name: 'Internet')];
      final p = await load();

      await p.addBill(
        rent(id: 'new-aug', month: aug, seriesId: 'new-aug'),
        applyToFuture: true,
      );

      expect(
        p.allBills.where((b) => b.month == sep && b.name == 'Rent'),
        hasLength(1),
        reason: 'the new bill has to show up in the month already opened',
      );
    });

    test('stays in its own month when not applied forward', () async {
      bills = [rent(id: 'sep-other', month: sep, name: 'Internet')];
      final p = await load();

      await p.addBill(rent(id: 'new-aug', month: aug, seriesId: 'new-aug'));

      expect(
          p.allBills.where((b) => b.month == sep && b.name == 'Rent'), isEmpty);
    });

    test('does not double up where the series already has a row', () async {
      bills = [
        rent(id: 'sep', month: sep, seriesId: 's1'),
        rent(id: 'oct-other', month: oct, name: 'Internet'),
      ];
      final p = await load();

      await p.addBill(
        rent(id: 'aug', month: aug, seriesId: 's1'),
        applyToFuture: true,
      );

      expect(p.allBills.where((b) => b.month == sep && b.seriesId == 's1'),
          hasLength(1));
    });
  });

  group('deleting a recurring bill', () {
    test('takes the unsettled months ahead with it', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
        rent(id: 'oct', month: oct, seriesId: 's1'),
      ];
      final p = await load();

      await p.deleteBill('aug', applyToFuture: true);

      expect(p.allBills, isEmpty);
    });

    test('deletes only the one row when scoped to this month', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      await p.deleteBill('aug');

      expect(p.allBills.map((b) => b.id), ['sep']);
    });

    test('spares a paid future month', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(
          id: 'sep',
          month: sep,
          seriesId: 's1',
          isPaid: true,
          transactionId: 'txn-1',
        ),
      ];
      final p = await load();

      await p.deleteBill('aug', applyToFuture: true);

      expect(p.allBills.map((b) => b.id), ['sep']);
    });

    test('ends the series, so the months left behind stop recurring', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
        rent(id: 'oct', month: oct, seriesId: 's1'),
      ];
      final p = await load(month: sep);

      await p.deleteBill('sep', applyToFuture: true);

      expect(p.allBills.map((b) => b.id), ['aug']);
      expect(billIn(p, aug).isRecurring, isFalse);
    });

    test('a spared paid month stops recurring too, so it cannot seed the next',
        () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(
          id: 'sep',
          month: sep,
          seriesId: 's1',
          isPaid: true,
          transactionId: 'txn-1',
        ),
      ];
      final p = await load();

      await p.deleteBill('aug', applyToFuture: true);

      expect(billIn(p, sep).isRecurring, isFalse);
    });

    test('scoping to this month leaves the series still repeating', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      await p.deleteBill('aug');

      expect(billIn(p, sep).isRecurring, isTrue);
    });

    test('a one-off delete never reaches other rows that have no series',
        () async {
      bills = [
        rent(id: 'aug', month: aug, isRecurring: false, name: 'Vet'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      // The one-off row's series is null. Matching rows by a null series would
      // sweep up every other unstamped row along with it.
      await p.deleteBill('aug', applyToFuture: true);

      expect(billIn(p, sep).isRecurring, isTrue);
    });
  });

  group('receivables and set-asides', () {
    test('a recurring receivable carries its new amount forward', () async {
      receivables = [
        salary(id: 'aug', month: aug, seriesId: 'r1'),
        salary(id: 'sep', month: sep, seriesId: 'r1'),
      ];
      final p = await load();

      final augR = p.allReceivables.firstWhere((r) => r.month == aug);
      await p.updateReceivable(augR.copyWith(amount: 45000),
          applyToFuture: true);

      expect(p.allReceivables.firstWhere((r) => r.month == sep).amount, 45000);
    });

    test('a received month keeps the amount that actually landed', () async {
      receivables = [
        salary(id: 'aug', month: aug, seriesId: 'r1'),
        salary(id: 'sep', month: sep, seriesId: 'r1', isReceived: true),
      ];
      final p = await load();

      final augR = p.allReceivables.firstWhere((r) => r.month == aug);
      await p.updateReceivable(augR.copyWith(amount: 45000),
          applyToFuture: true);

      expect(p.allReceivables.firstWhere((r) => r.month == sep).amount, 40000);
    });

    test('a propagated expected date is re-pinned into each target month',
        () async {
      receivables = [
        salary(id: 'aug', month: aug, seriesId: 'r1'),
        salary(id: 'sep', month: sep, seriesId: 'r1'),
      ];
      final p = await load();

      final augR = p.allReceivables.firstWhere((r) => r.month == aug);
      await p.updateReceivable(
        augR.copyWith(expectedDate: _dayIn(aug, 25)),
        applyToFuture: true,
      );

      final sepR = p.allReceivables.firstWhere((r) => r.month == sep);
      expect(sepR.expectedDate, _dayIn(sep, 25),
          reason: 'the day travels, the month does not');
    });

    test('a recurring set-aside carries its new allocation forward', () async {
      expenses = [
        fund(id: 'aug', month: aug, seriesId: 'e1'),
        fund(id: 'sep', month: sep, seriesId: 'e1'),
      ];
      final p = await load();

      final augE = p.allBudgetedExpenses.firstWhere((e) => e.month == aug);
      await p.updateBudgetedExpense(augE.copyWith(allocatedAmount: 4500),
          applyToFuture: true);

      expect(
        p.allBudgetedExpenses.firstWhere((e) => e.month == sep).allocatedAmount,
        4500,
      );
    });

    test('a funded set-aside is left as it stands', () async {
      expenses = [
        fund(id: 'aug', month: aug, seriesId: 'e1'),
        fund(id: 'sep', month: sep, seriesId: 'e1', isPaid: true, spent: 3000),
      ];
      final p = await load();

      final augE = p.allBudgetedExpenses.firstWhere((e) => e.month == aug);
      await p.updateBudgetedExpense(augE.copyWith(allocatedAmount: 4500),
          applyToFuture: true);

      final sepE = p.allBudgetedExpenses.firstWhere((e) => e.month == sep);
      expect(sepE.allocatedAmount, 3000);
      expect(sepE.spentAmount, 3000,
          reason: 'money already set aside is not re-planned');
    });
  });

  // Deleting the months was never the whole job. A month with nothing in it
  // is re-seeded from the previous month's recurring rows the moment it is
  // opened, so clearing a salary out of September and beyond only to have
  // August put it straight back is what had users deleting the same item
  // month after month. Ending the series is what stops that, so these pin the
  // flag *and* the round trip through the auto-copy pass that undid the delete.
  group('a deleted series stays deleted', () {
    test('a cleared month is not seeded again from the month before it',
        () async {
      receivables = [
        salary(id: 'aug', month: aug, seriesId: 's1'),
        salary(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load(month: sep);

      await p.deleteReceivable('sep', applyToFuture: true);
      // Paging away and back is what resurrected it: September is empty now,
      // and August was still flagged as recurring.
      await p.setMonth(aug);
      await p.setMonth(sep);

      expect(p.allReceivables.map((r) => r.id), ['aug']);
      expect(p.allReceivables.single.isRecurring, isFalse);
    });

    test('nor is the month after the last one deleted', () async {
      receivables = [
        salary(id: 'aug', month: aug, seriesId: 's1'),
        salary(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load(month: aug);

      await p.deleteReceivable('aug', applyToFuture: true);
      await p.setMonth(oct);

      expect(p.allReceivables, isEmpty);
    });

    test('a set-aside series ends the same way', () async {
      expenses = [
        fund(id: 'aug', month: aug, seriesId: 'e1'),
        fund(id: 'sep', month: sep, seriesId: 'e1'),
      ];
      final p = await load(month: sep);

      await p.deleteBudgetedExpense('sep', applyToFuture: true);
      await p.setMonth(sep);

      expect(p.allBudgetedExpenses.map((e) => e.id), ['aug']);
      expect(p.allBudgetedExpenses.single.isRecurring, isFalse);
    });

    test('a bill series ends the same way', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load(month: sep);

      await p.deleteBill('sep', applyToFuture: true);
      await p.setMonth(sep);

      expect(p.allBills.map((b) => b.id), ['aug']);
      expect(billIn(p, aug).isRecurring, isFalse);
    });

    test('a this-month-only delete still lets the series carry on', () async {
      receivables = [
        salary(id: 'aug', month: aug, seriesId: 's1'),
        salary(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load(month: sep);

      await p.deleteReceivable('sep');
      await p.setMonth(sep);

      expect(p.allReceivables.any((r) => r.month == sep), isTrue,
          reason: 'the series was left running, so September seeds again');
    });

    test('an unrelated series in the same month keeps repeating', () async {
      receivables = [
        salary(id: 'pay-aug', month: aug, seriesId: 's1'),
        salary(
          id: 'rent-aug',
          month: aug,
          name: 'Rental Income',
          seriesId: 's2',
        ),
      ];
      final p = await load();

      await p.deleteReceivable('pay-aug', applyToFuture: true);

      expect(p.allReceivables.single.id, 'rent-aug');
      expect(p.allReceivables.single.isRecurring, isTrue);
    });
  });

  // The batch bar is the delete most people reach for, and it used to be the
  // one that never asked. These pin that ticking a recurring row in
  // multi-select reaches as far as opening it and choosing "All months" does.
  group('batch delete', () {
    test('takes the series with it and ends it', () async {
      receivables = [
        salary(id: 'jul', month: jul, seriesId: 's1'),
        salary(id: 'aug', month: aug, seriesId: 's1'),
        salary(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      final deleted = await p.deleteReceivables(['aug'], applyToFuture: true);
      await p.setMonth(aug);

      expect(deleted, 2, reason: 'August, and the September row ahead of it');
      expect(p.allReceivables.map((r) => r.id), ['jul']);
      expect(p.allReceivables.single.isRecurring, isFalse);
    });

    test('leaves the series running when scoped to this month', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      final deleted = await p.deleteBills(['aug']);

      expect(deleted, 1);
      expect(billIn(p, sep).isRecurring, isTrue);
    });

    test('only ends the series in a mixed selection that has one', () async {
      bills = [
        rent(id: 'vet', month: aug, isRecurring: false, name: 'Vet'),
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
      ];
      final p = await load();

      final deleted = await p.deleteBills(['vet', 'aug'], applyToFuture: true);

      expect(deleted, 3,
          reason: 'the one-off, August, and September ahead of it');
      expect(p.allBills, isEmpty);
    });

    test('a set-aside selection ends its series too', () async {
      expenses = [
        fund(id: 'aug', month: aug, seriesId: 'e1'),
        fund(id: 'sep', month: sep, seriesId: 'e1'),
      ];
      final p = await load();

      final deleted =
          await p.deleteBudgetedExpenses(['aug'], applyToFuture: true);
      await p.setMonth(sep);

      expect(deleted, 2);
      expect(p.allBudgetedExpenses, isEmpty);
    });

    test('two selected months of one series do not double-count its future',
        () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
        rent(id: 'oct', month: oct, seriesId: 's1'),
      ];
      final p = await load();

      final reach = p.billBatchSeriesReach(['aug', 'sep']);

      expect(reach.recurring, 2);
      // September and October lie ahead of August, October ahead of September.
      // Only October is a month the selection doesn't already cover.
      expect(reach.extraMonths, 1);
    });

    test('a selection with nothing recurring has nothing to ask about',
        () async {
      bills = [rent(id: 'vet', month: aug, isRecurring: false, name: 'Vet')];
      final p = await load();

      final reach = p.billBatchSeriesReach(['vet']);

      expect(reach.recurring, 0);
      expect(reach.extraMonths, 0);
    });

    test('a settled month ahead is not counted as reachable', () async {
      receivables = [
        salary(id: 'aug', month: aug, seriesId: 's1'),
        salary(id: 'sep', month: sep, seriesId: 's1', isReceived: true),
      ];
      final p = await load();

      final reach = p.receivableBatchSeriesReach(['aug']);

      expect(reach.recurring, 1);
      expect(reach.extraMonths, 0, reason: 'money already received stays put');
    });
  });

  group('seriesId', () {
    test('backfills rows saved before the field existed', () async {
      bills = [
        rent(id: 'jul', month: jul),
        rent(id: 'aug', month: aug),
        rent(id: 'sep', month: sep),
      ];
      final p = await load();

      final series = p.allBills.map((b) => b.seriesId).toSet();
      expect(series, hasLength(1), reason: 'one item, one series');
      expect(series.single, 'jul',
          reason: 'the earliest month lends its id, so two devices backfilling '
              'the same history land on the same token');
    });

    test('keeps unrelated items in separate series', () async {
      bills = [
        rent(id: 'rent-aug', month: aug),
        rent(id: 'net-aug', month: aug, name: 'Internet'),
        rent(id: 'net-sep', month: sep, name: 'Internet'),
      ];
      final p = await load();

      final rentSeries =
          p.allBills.firstWhere((b) => b.id == 'rent-aug').seriesId;
      final netSeries =
          p.allBills.firstWhere((b) => b.id == 'net-aug').seriesId;
      expect(rentSeries, isNot(netSeries));
      expect(
          p.allBills.firstWhere((b) => b.id == 'net-sep').seriesId, netSeries);
    });

    test('leaves one-off bills out of any series', () async {
      bills = [rent(id: 'aug', month: aug, isRecurring: false)];
      final p = await load();

      expect(p.allBills.single.seriesId, isNull);
    });

    test('a backfilled series is then editable across months', () async {
      // The whole point of the backfill: a user with months of history gets the
      // fix applied to the data they already have, not just to new items.
      bills = [
        rent(id: 'aug', month: aug),
        rent(id: 'sep', month: sep),
      ];
      final p = await load();

      await p.updateBill(
        billIn(p, aug).copyWith(amount: 18000),
        applyToFuture: true,
      );

      expect(billIn(p, sep).amount, 18000);
    });

    test('a generated month inherits its parent series', () async {
      bills = [rent(id: 'aug', month: aug, seriesId: 's1')];
      final p = await load();

      await p.setMonth(sep);

      expect(billIn(p, sep).seriesId, 's1');
    });
  });

  group('reach counts', () {
    test('counts the months an edit would touch', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(id: 'sep', month: sep, seriesId: 's1'),
        rent(id: 'oct', month: oct, seriesId: 's1'),
      ];
      final p = await load();

      expect(p.futureBillReach(month: aug, existing: billIn(p, aug)), 2);
    });

    test('a settled future month is not offered up as editable', () async {
      bills = [
        rent(id: 'aug', month: aug, seriesId: 's1'),
        rent(
          id: 'sep',
          month: sep,
          seriesId: 's1',
          isPaid: true,
          transactionId: 'txn-1',
        ),
      ];
      final p = await load();

      expect(p.futureBillReach(month: aug, existing: billIn(p, aug)), 0,
          reason: 'nothing to change means no choice worth showing');
    });

    test('a new item reaches the months already generated', () async {
      bills = [rent(id: 'sep-other', month: sep, name: 'Internet')];
      final p = await load();

      expect(p.futureBillReach(month: aug), 1);
    });

    test('reaches nothing when there is no later month at all', () async {
      bills = [rent(id: 'aug', month: aug, seriesId: 's1')];
      final p = await load();

      expect(p.futureBillReach(month: aug, existing: billIn(p, aug)), 0);
    });
  });
}
