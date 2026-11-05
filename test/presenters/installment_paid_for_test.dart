import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

/// Plan 067: a plan bought for someone else keeps one receivable per payment
/// month, whichever way the plan is saved, and the form's review shows what
/// the save will do before anything is written.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;
  late LedgerPresenter ledger;
  late InstallmentPresenter installments;
  late BillsReceivablesPresenter bills;

  late List<FinancialAccount> accountsState;
  late List<TransactionRecord> txnState;
  late List<Installment> planState;
  late List<Receivable> receivableState;

  final tech = FinanceCategory(
    id: 'cat-tech',
    name: 'Tech',
    colorHex: '#3366FF',
    icon: 'phone',
    type: CategoryType.expense,
  );

  // "Madness Limit": statement closes the 15th, payment due the 4th.
  final card = FinancialAccount(
    id: 'bpi',
    name: 'Madness Limit',
    category: AccountCategory.creditCard,
    balance: 0,
    creditLimit: 100000,
    statementDay: 15,
    paymentDueDay: 4,
    colorHex: '#AA0000',
    icon: 'credit_card',
  );

  // A BNPL with no billing cycle.
  final billease = FinancialAccount(
    id: 'billease',
    name: 'BillEase',
    category: AccountCategory.bnpl,
    balance: 0,
    colorHex: '#00AA88',
    icon: 'wallet',
  );

  void build() {
    ledger = LedgerPresenter(storage, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
    bills = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: notifications,
      installments: installments,
      clock: () => DateTime(2026, 10, 30),
    );
  }

  Future<void> loadAll() async {
    await ledger.load();
    await installments.load();
    await bills.load();
  }

  /// Lets the unawaited reconcile kicked off by a notify finish.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Installment draft({
    Installment? existing,
    String? paidFor = 'Papa',
    int months = 3,
    double monthly = 1000,
    String start = '2026-11',
    int deferral = 0,
    String accountId = 'bpi',
    DateTime? bought,
  }) =>
      installments.buildInstallment(
        existing: existing,
        name: 'Xiaomi Redmi Note 15',
        accountId: accountId,
        totalAmount: monthly * months,
        monthlyAmount: monthly,
        totalMonths: months,
        startMonth: start,
        purchaseDate: bought ?? DateTime(2026, 10, 10),
        deferralMonths: deferral,
        categoryId: 'cat-tech',
        paidForName: paidFor,
      );

  List<Receivable> linked(String planId) =>
      bills.allReceivables.where((r) => r.installmentId == planId).toList()
        ..sort((a, b) => a.installmentNumber!.compareTo(b.installmentNumber!));

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();

    accountsState = [card, billease];
    txnState = [];
    planState = [];
    receivableState = [];

    when(storage.loadAccounts()).thenAnswer((_) async => accountsState);
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      accountsState =
          List<FinancialAccount>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [tech]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => txnState);
    when(storage.saveTransactions(any)).thenAnswer((inv) async {
      txnState =
          List<TransactionRecord>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadInstallments()).thenAnswer((_) async => planState);
    when(storage.saveInstallments(any)).thenAnswer((inv) async {
      planState = List<Installment>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadBills()).thenAnswer((_) async => <Bill>[]);
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.loadReceivables()).thenAnswer((_) async => receivableState);
    when(storage.saveReceivables(any)).thenAnswer((inv) async {
      receivableState =
          List<Receivable>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadDismissedStatementKeys())
        .thenAnswer((_) async => <String>{});
    when(storage.saveDismissedStatementKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.awardStat(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    build();
  });

  group('receivables follow the plan', () {
    test('saving a plan for someone creates one receivable per month',
        () async {
      await loadAll();
      final plan = draft();
      await installments.saveInstallment(plan, isEdit: false);
      await settle();

      final made = linked(plan.id);
      expect(made.map((r) => r.month), ['2026-11', '2026-12', '2027-01']);
      expect(made.first.name, 'Papa — Xiaomi Redmi Note 15 (1/3)');
      expect(made.first.amount, 1000);
      // The card's due date in that month.
      expect(made.first.expectedDate, DateTime(2026, 11, 4));
      expect(made.first.categoryId, 'cat-tech');
      expect(made.first.createdAt, DateTime(2026, 10, 30));
      // Persisted, not only in memory.
      expect(receivableState.where((r) => r.installmentId == plan.id),
          hasLength(3));
    });

    test('a plan for yourself creates no receivables', () async {
      await loadAll();
      await installments.saveInstallment(draft(paidFor: null), isEdit: false);
      await settle();
      expect(bills.allReceivables, isEmpty);
    });

    test('an edit moves open receivables and keeps a received one', () async {
      await loadAll();
      final plan = draft();
      await installments.saveInstallment(plan, isEdit: false);
      await settle();
      final first = linked(plan.id).first;
      await bills.markReceivableReceived(first.id,
          receivedAmount: 1000, recordInLedger: false);

      await installments.saveInstallment(
          draft(existing: plan, monthly: 1500, months: 4),
          isEdit: true);
      await settle();

      final after = linked(plan.id);
      expect(after.map((r) => r.amount), [1000, 1500, 1500, 1500]);
      expect(after.first.isReceived, isTrue);
      expect(after.first.name, 'Papa — Xiaomi Redmi Note 15 (1/3)',
          reason: 'a received receivable is never changed');
      expect(after.last.month, '2027-02');
    });

    test('toggle off deletes open ones, unlinks the received one', () async {
      await loadAll();
      final plan = draft();
      await installments.saveInstallment(plan, isEdit: false);
      await settle();
      final first = linked(plan.id).first;
      await bills.markReceivableReceived(first.id,
          receivedAmount: 1000, recordInLedger: false);

      await installments.saveInstallment(draft(existing: plan, paidFor: null),
          isEdit: true);
      await settle();

      expect(linked(plan.id), isEmpty);
      final kept = bills.allReceivables.single;
      expect(kept.id, first.id);
      expect(kept.isReceived, isTrue);
      expect(kept.installmentId, isNull);
    });

    test('deleting the plan deletes its open receivables', () async {
      await loadAll();
      final plan = draft();
      await installments.saveInstallment(plan, isEdit: false);
      await settle();
      await installments.deleteInstallment(plan.id);
      await settle();
      expect(bills.allReceivables, isEmpty);
    });

    test('an edit that leaves the person out keeps the person', () async {
      await loadAll();
      final plan = draft();
      final edited = installments.buildInstallment(
        existing: plan,
        name: plan.name,
        accountId: plan.accountId,
        totalAmount: plan.totalAmount,
        monthlyAmount: plan.monthlyAmount,
        totalMonths: plan.totalMonths,
        startMonth: plan.startMonth,
        purchaseDate: plan.purchaseDate!,
      );
      expect(edited.paidForName, 'Papa');
      expect(draft(paidFor: '  ').paidForName, isNull);
    });

    test('a launch does not bring back a receivable deleted by hand', () async {
      await loadAll();
      final plan = draft();
      await installments.saveInstallment(plan, isEdit: false);
      await settle();
      await bills.deleteReceivable(linked(plan.id).last.id);

      build();
      await loadAll();
      await settle();
      expect(linked(plan.id), hasLength(2));
    });
  });

  group('review step', () {
    test('lists the schedule and the first statement', () async {
      await loadAll();
      // Bought Oct 10, before the 15th: closes Oct 15, due Nov 4.
      final review = installments.reviewPlan(draft());
      expect(review.firstMonth, 'Nov 2026');
      expect(review.lastMonth, 'Jan 2027');
      expect(review.monthly, '₱1,000.00 × 3');
      expect(review.total, '₱3,000.00');
      expect(review.deferral, 'None');
      expect(review.statementClose, 'Oct 15, 2026');
      expect(review.firstDue, 'Nov 4, 2026');
      expect(review.startMonthWarning, isNull, reason: 'add mode');
    });

    test('a card with no billing cycle says so', () async {
      await loadAll();
      final review =
          installments.reviewPlan(draft(accountId: 'billease', deferral: 1));
      expect(review.statementClose, 'No billing cycle on this card');
      expect(review.firstDue, 'Not set');
      expect(review.deferral, '1 month');
    });

    test('flags a stored start month the card cycle disagrees with', () async {
      // The Panasonic Refrigerator plan: bought Sep 25 on a card closing the
      // 15th, 3 months deferred, stored with start month Dec 2026 — the
      // no-cycle result. The cycle gives Nov due + 3 = Feb 2027.
      await loadAll();
      final stored = Installment(
        id: 'panasonic',
        name: 'Panasonic Refrigerator',
        accountId: 'bpi',
        totalAmount: 36000,
        monthlyAmount: 3000,
        totalMonths: 12,
        startMonth: '2026-12',
        purchaseDate: DateTime(2026, 9, 25),
        deferralMonths: 3,
      );
      final edit = installments.buildInstallment(
        existing: stored,
        name: stored.name,
        accountId: stored.accountId,
        totalAmount: stored.totalAmount,
        monthlyAmount: stored.monthlyAmount,
        totalMonths: stored.totalMonths,
        startMonth: stored.startMonth,
        purchaseDate: stored.purchaseDate!,
        deferralMonths: stored.deferralMonths,
      );
      final review = installments.reviewPlan(edit);
      expect(review.startMonthWarning,
          'Set by hand: Dec 2026 · computed: Feb 2027');
      expect(review.suggestedStartMonth, '2027-02');
      expect(review.suggestedStartLabel, 'Use Feb 2027');
      // The stored month's own statement: closes Nov 15, due Dec 4.
      expect(review.statementClose, 'Nov 15, 2026');
      expect(review.firstDue, 'Dec 4, 2026');

      // Taking the suggestion clears the warning.
      final fixed =
          installments.reviewPlan(edit.copyWith(startMonth: '2027-02'));
      expect(fixed.startMonthWarning, isNull);
      expect(fixed.statementClose, 'Jan 15, 2027');
      expect(fixed.firstDue, 'Feb 4, 2027');
      // Only the review changed: the stored plan is untouched.
      expect(stored.startMonth, '2026-12');
    });

    test('receivable preview: new plan', () async {
      await loadAll();
      final preview = bills.installmentReceivablePreview(draft())!;
      expect(preview.title, 'Receivables from Papa');
      expect(preview.summary, '3 new');
      expect(preview.rows.map((r) => r.month),
          ['Nov 2026', 'Dec 2026', 'Jan 2027']);
      expect(preview.rows.first.amount, '₱1,000.00');
      expect(preview.rows.first.status, 'New');
      // A preview writes nothing.
      expect(bills.allReceivables, isEmpty);
    });

    test('receivable preview: edit with a received one', () async {
      await loadAll();
      final plan = draft();
      await installments.saveInstallment(plan, isEdit: false);
      await settle();
      await bills.markReceivableReceived(linked(plan.id).first.id,
          receivedAmount: 1000, recordInLedger: false);

      final preview =
          bills.installmentReceivablePreview(draft(existing: plan, months: 2))!;
      // 3 → 2 months: payment 1 was received, 2 is renamed (2/2), 3 goes.
      expect(preview.summary, '1 updated · 1 removed · 1 received, kept');
      expect(preview.rows.map((r) => r.status),
          ['Received · kept', 'Updated', 'Removed']);

      final off = bills
          .installmentReceivablePreview(draft(existing: plan, paidFor: null))!;
      expect(off.title, 'Receivables to remove');
      expect(off.summary, '2 removed · 1 received, kept');
      expect(off.rows.where((r) => r.isRemoval), hasLength(2));
    });

    test('receivable preview: nothing for a plan for yourself', () async {
      await loadAll();
      expect(bills.installmentReceivablePreview(draft(paidFor: null)), isNull);
    });
  });

  test('known people: plan names first, then reimbursement names', () async {
    txnState = [
      TransactionRecord(
        id: 't1',
        date: DateTime(2026, 10, 1),
        accountId: 'bpi',
        categoryId: 'cat-tech',
        amount: 500,
        type: TransactionType.outflow,
        description: 'Lunch',
        month: '2026-10',
        owedBy: 'Jana',
      ),
      TransactionRecord(
        id: 't2',
        date: DateTime(2026, 10, 2),
        accountId: 'bpi',
        categoryId: 'cat-tech',
        amount: 300,
        type: TransactionType.outflow,
        description: 'Taxi',
        month: '2026-10',
        owedBy: 'papa',
      ),
    ];
    await loadAll();
    await installments.saveInstallment(draft(), isEdit: false);
    expect(installments.knownPeople, ['Papa', 'Jana']);
  });
}
