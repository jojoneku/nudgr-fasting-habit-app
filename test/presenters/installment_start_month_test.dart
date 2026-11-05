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

/// Plan 068: a plan's first payment month is computed from its card's cycle,
/// its purchase date and its deferral — unless it was set by hand. Plans saved
/// before this are migrated without any month changing.
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
  final bpi = FinancialAccount(
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

  // ShopeePay-style BNPL with no billing cycle.
  final spay = FinancialAccount(
    id: 'spay',
    name: 'SPayLater',
    category: AccountCategory.bnpl,
    balance: 0,
    creditLimit: 20000,
    colorHex: '#EE4D2D',
    icon: 'wallet',
  );

  Installment plan(
    String id, {
    String accountId = 'bpi',
    required String start,
    required DateTime bought,
    int deferral = 0,
    int months = 3,
    StartMonthSource? source,
    String? paidFor,
  }) =>
      Installment(
        id: id,
        name: 'Plan $id',
        accountId: accountId,
        totalAmount: 1000.0 * months,
        monthlyAmount: 1000,
        totalMonths: months,
        startMonth: start,
        purchaseDate: bought,
        deferralMonths: deferral,
        categoryId: 'cat-tech',
        startMonthSource: source,
        paidForName: paidFor,
      );

  // Bought Sep 25 (after the 15th) → Oct 15 statement, due Nov → + 3 = Feb
  // 2027. Stored Dec 2026: the no-cycle result.
  Installment fridge() => plan('fridge',
      start: '2026-12', bought: DateTime(2026, 9, 25), deferral: 3);

  // Bought Oct 10 → Oct 15 statement, due Nov 4: stored as computed.
  Installment tv() =>
      plan('tv', start: '2026-11', bought: DateTime(2026, 10, 10));

  // On the BNPL: no cycle, stored Oct for a Sep purchase.
  Installment camera() => plan('camera',
      accountId: 'spay', start: '2026-10', bought: DateTime(2026, 9, 12));

  // Differs from the cycle (Jun 10 → due Jul) and one month is billed.
  Installment billed() =>
      plan('billed', start: '2026-08', bought: DateTime(2026, 6, 10));

  TransactionRecord charge(String planId) => TransactionRecord(
        id: 'chg-$planId',
        date: DateTime(2026, 7, 15),
        accountId: 'bpi',
        categoryId: 'cat-tech',
        amount: 1000,
        type: TransactionType.outflow,
        description: 'Plan $planId — Installment 1/3',
        month: '2026-08',
        installmentId: planId,
      );

  /// Builds the presenters over the test's data, then loads them. Built
  /// here, not in setUp, so a test can set its data first: the constructors
  /// start loading at once.
  Future<void> loadAll() async {
    ledger = LedgerPresenter(storage, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
    bills = BillsReceivablesPresenter(storage, ledger, stats,
        notifications: notifications,
        installments: installments,
        // Before the Oct 15 close, so no month of these plans is billed
        // by a statement yet.
        clock: () => DateTime(2026, 10, 1));
    await ledger.load();
    await installments.load();
    await bills.load();
    await Future<void>.delayed(Duration.zero);
  }

  /// Lets the unawaited persist and the bills reconcile finish.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Installment stored(String id) => installments.findById(id)!;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    accountsState = [bpi, spay];
    txnState = [];
    planState = [fridge(), tv(), camera(), billed()];
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
  });

  test('the source round-trips through JSON; an old row loads as null', () {
    final p = fridge().copyWith(startMonthSource: StartMonthSource.review);
    expect(Installment.fromJson(p.toJson()).startMonthSource,
        StartMonthSource.review);
    expect(Installment.fromJson(fridge().toJson()).startMonthSource, isNull);
    expect(fridge().toJson().containsKey('startMonthSource'), isFalse);
  });

  group('migration of plans saved before Plan 068', () {
    setUp(() => txnState = [charge('billed')]);

    test('gives every plan a source and changes no month', () async {
      await loadAll();

      expect(stored('fridge').startMonthSource, StartMonthSource.review);
      expect(stored('tv').startMonthSource, StartMonthSource.computed);
      expect(stored('camera').startMonthSource, StartMonthSource.manual,
          reason: 'no cycle on the card');
      expect(stored('billed').startMonthSource, StartMonthSource.manual,
          reason: 'a month is billed');

      expect(stored('fridge').startMonth, '2026-12');
      expect(stored('tv').startMonth, '2026-11');
      expect(stored('camera').startMonth, '2026-10');
      expect(stored('billed').startMonth, '2026-08');
      // Persisted, not only in memory.
      await settle();
      expect(planState.every((p) => p.startMonthSource != null), isTrue);
    });

    test('lists only the plan that waits for a decision', () async {
      await loadAll();
      expect(installments.startMonthReviewBanner,
          "1 plan's first payment month differs from its card's cycle");
      final item = installments.startMonthReviewItems.single;
      expect(item.id, 'fridge');
      expect(item.detail, 'Madness Limit · bought Sep 25 · deferred 3 mos');
      expect(item.stored, 'Saved: Dec 2026');
      expect(item.computed, 'Card cycle: Feb 2027');
      expect(item.useLabel, 'Use Feb 2027');
      expect(item.keepLabel, 'Keep Dec 2026');
    });

    test('"Use Feb 2027" takes the computed month', () async {
      await loadAll();
      await installments.useComputedStartMonth('fridge');
      expect(stored('fridge').startMonth, '2027-02');
      expect(stored('fridge').startMonthSource, StartMonthSource.computed);
      expect(installments.startMonthReviewItems, isEmpty);
      expect(installments.startMonthReviewBanner, isNull);
    });

    test('"Keep Dec 2026" sets it by hand and clears the list', () async {
      await loadAll();
      await installments.keepStartMonth('fridge');
      expect(stored('fridge').startMonth, '2026-12');
      expect(stored('fridge').startMonthSource, StartMonthSource.manual);
      expect(installments.startMonthReviewItems, isEmpty);
    });

    test("Nudgy's find line says where the month comes from", () async {
      await loadAll();
      expect(installments.startMonthNote(stored('fridge')),
          'not confirmed; the card cycle gives 2027-02');
      expect(installments.startMonthNote(stored('tv')),
          'computed from the card cycle');
      expect(installments.startMonthNote(stored('camera')), isNull);
      expect(installments.startMonthNote(stored('billed')),
          'set by hand; the card cycle gives 2026-07');
    });
  });

  group('a computed month follows the card', () {
    test('an edit to the deferral recomputes it; a manual one stays', () async {
      await loadAll();
      await installments.keepStartMonth('fridge');

      await installments
          .updateInstallment(stored('tv').copyWith(deferralMonths: 2));
      expect(stored('tv').startMonth, '2027-01');

      await installments
          .updateInstallment(stored('fridge').copyWith(deferralMonths: 1));
      expect(stored('fridge').startMonth, '2026-12');
    });

    test("a change to the card's cycle moves computed plans only", () async {
      txnState = [charge('billed')];
      await loadAll();
      await installments.keepStartMonth('fridge');

      // Statement day 15 → 5: Oct 10 now lands on the Nov 5 statement, due
      // Dec 4.
      await ledger.saveAccount(bpi.copyWith(statementDay: 5));
      await settle();

      expect(stored('tv').startMonth, '2026-12');
      expect(stored('fridge').startMonth, '2026-12', reason: 'manual');
      expect(stored('billed').startMonth, '2026-08', reason: 'billed');
      expect(planState.firstWhere((p) => p.id == 'tv').startMonth, '2026-12');
    });

    test('a computed plan with a billed month is not moved', () async {
      await loadAll();
      expect(stored('tv').startMonthSource, StartMonthSource.computed);
      await ledger.addTransaction(charge('tv'));
      await ledger.saveAccount(bpi.copyWith(statementDay: 5));
      await settle();
      expect(stored('tv').startMonth, '2026-11');
      expect(installments.startMonthNote(stored('tv')),
          'kept because a month is billed; the card cycle now gives 2026-12');
    });

    test('a card that gets a cycle decides its plans again', () async {
      planState = [
        camera(), // Sep 12 → closes Oct 1, due Oct 15: agrees
        plan('cable',
            accountId: 'spay', start: '2026-11', bought: DateTime(2026, 9, 12)),
      ];
      await loadAll();
      expect(stored('camera').startMonthSource, StartMonthSource.manual);
      expect(stored('cable').startMonthSource, StartMonthSource.manual);

      await ledger
          .saveAccount(spay.copyWith(statementDay: 1, paymentDueDay: 15));
      await settle();

      expect(stored('camera').startMonthSource, StartMonthSource.computed);
      expect(stored('cable').startMonthSource, StartMonthSource.review);
      expect(stored('cable').startMonth, '2026-11');
    });

    test('the receivables of a plan for someone follow a moved month',
        () async {
      planState = [];
      await loadAll();
      await installments.saveInstallment(
        plan('gift',
            start: '2026-11',
            bought: DateTime(2026, 10, 10),
            source: StartMonthSource.computed,
            paidFor: 'Papa'),
        isEdit: false,
      );
      await settle();
      List<String> months() => [
            for (final r
                in bills.allReceivables.where((r) => r.installmentId == 'gift'))
              r.month
          ]..sort();
      expect(months(), ['2026-11', '2026-12', '2027-01']);

      await ledger.saveAccount(bpi.copyWith(statementDay: 5));
      await settle();
      await settle();
      expect(stored('gift').startMonth, '2026-12');
      expect(months(), ['2026-12', '2027-01', '2027-02']);
    });

    test("the ledger's purchase edit keeps a month set by hand", () async {
      await loadAll();
      await installments.keepStartMonth('fridge');
      final p = stored('fridge');
      final moved = ledger.editedPlan(
        p,
        previousDate: p.purchaseDate!,
        account: bpi,
        accountId: 'bpi',
        amount: p.totalAmount,
        months: p.totalMonths,
        interestRate: 0,
        date: DateTime(2026, 9, 10),
        name: p.name,
        note: null,
        categoryId: p.categoryId,
      );
      expect(moved.startMonth, '2026-12');
      expect(moved.startMonthSource, StartMonthSource.manual);

      final computed = ledger.editedPlan(
        stored('tv'),
        previousDate: DateTime(2026, 10, 10),
        account: bpi,
        accountId: 'bpi',
        amount: 3000,
        months: 3,
        interestRate: 0,
        date: DateTime(2026, 10, 20),
        name: 'Plan tv',
        note: null,
        categoryId: 'cat-tech',
      );
      // After the 15th: the Nov 15 statement, due Dec 4.
      expect(computed.startMonth, '2026-12');
    });
  });

  group('form helpers', () {
    test('the form treats review and manual plans as set by hand', () async {
      await loadAll();
      expect(installments.isStartMonthPinned(stored('fridge')), isTrue);
      expect(installments.isStartMonthPinned(stored('tv')), isFalse);
      expect(installments.isStartMonthPinned(stored('camera')), isFalse,
          reason: 'no cycle: the form keeps suggesting a month');
      expect(installments.isStartMonthPinned(fridge()), isTrue,
          reason: 'not migrated yet, and it differs');
    });

    test('the hint under a month set by hand', () async {
      await loadAll();
      expect(
        installments.pinnedStartMonthHint(
          accountId: 'bpi',
          purchaseDate: DateTime(2026, 9, 25),
          deferralMonths: 3,
          startMonth: '2026-12',
        ),
        'Set by hand · computed: Feb 2027',
      );
      expect(
        installments.pinnedStartMonthHint(
          accountId: 'spay',
          purchaseDate: DateTime(2026, 9, 25),
          deferralMonths: 0,
          startMonth: '2026-12',
        ),
        isNull,
      );
    });

    test('the review step of a billed plan has no "Use" button', () async {
      txnState = [charge('billed')];
      await loadAll();
      final review = installments.reviewPlan(stored('billed'));
      expect(review.startMonthWarning,
          "Billed from Aug 2026 · the card's cycle now gives Jul 2026");
      expect(review.suggestedStartMonth, isNull);
    });

    test('the review step shows a computed month as it will be saved',
        () async {
      await loadAll();
      // The form still shows Nov, but the deferral moved the computed month.
      final review = installments.reviewPlan(stored('tv').copyWith(
          deferralMonths: 1, startMonthSource: StartMonthSource.computed));
      expect(review.firstMonth, 'Dec 2026');
      expect(review.startMonthWarning, isNull);
    });
  });
}
