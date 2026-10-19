import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import '../mocks.mocks.dart';

/// The next-month forecast on the real presenter graph: the bills presenter
/// files the statement and charges the installment months onto the card when
/// it closes, and the forecast must count each peso once — as an estimate
/// before the close, inside the filed statement after it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  late List<FinancialAccount> accountsState;
  late List<TransactionRecord> txnState;
  late List<Installment> planState;
  late List<Bill> billState;

  final shopping = FinanceCategory(
    id: 'cat-shop',
    name: 'Shopping',
    colorHex: '#3366FF',
    icon: 'bag',
    type: CategoryType.expense,
  );

  final bank = FinancialAccount(
    id: 'bank',
    name: 'Bank',
    category: AccountCategory.bank,
    balance: 50000,
    colorHex: '#123456',
    icon: 'bank',
  );

  // Closes the 25th, due the 10th: the Oct 25 statement falls due Nov 10.
  final card = FinancialAccount(
    id: 'card',
    name: 'Card',
    category: AccountCategory.creditCard,
    balance: 845.69,
    creditLimit: 20000,
    statementDay: 25,
    paymentDueDay: 10,
    colorHex: '#EE4D2D',
    icon: 'card',
  );

  // Its first month bills at the Oct 25 close — the first statement due in
  // or after November.
  final phone = Installment(
    id: 'phone',
    name: 'Phone',
    accountId: 'card',
    totalAmount: 1800,
    monthlyAmount: 600,
    totalMonths: 3,
    startMonth: '2026-11',
    purchaseDate: DateTime(2026, 10, 1),
    categoryId: 'cat-shop',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();

    accountsState = [card, bank];
    txnState = [];
    planState = [phone];
    billState = [];

    when(storage.loadAccounts()).thenAnswer((_) async => accountsState);
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      accountsState =
          List<FinancialAccount>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [shopping]);
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
    when(storage.loadBills()).thenAnswer((_) async => billState);
    when(storage.saveBills(any)).thenAnswer((inv) async {
      billState = List<Bill>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadBudgets()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
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

  /// Ledger, plans, bills (statements generated) and the dashboard, at [now].
  Future<
      ({
        TreasuryDashboardPresenter dashboard,
        BillsReceivablesPresenter bills
      })> buildGraph(DateTime now) async {
    DateTime clock() => now;
    final ledger = LedgerPresenter(storage, stats);
    final installments = InstallmentPresenter(storage, ledger, stats);
    ledger.watchInstallmentPlans(
        installments, () => installments.allInstallments);
    final bills = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: notifications,
      installments: installments,
      clock: clock,
    );
    await ledger.load();
    await installments.load();
    await bills.load();
    final dashboard = TreasuryDashboardPresenter(
        storage, ledger, null, bills, clock, installments);
    await dashboard.load();
    return (dashboard: dashboard, bills: bills);
  }

  test('before the close: the statement is estimated, installment included',
      () async {
    final g = await buildGraph(DateTime(2026, 10, 20));
    final f = g.dashboard.nextMonthForecast;

    expect(g.bills.allBills.where((b) => b.month == '2026-11'), isEmpty);
    expect(f.bills, closeTo(845.69, 0.005));
    expect(f.installments, 600);
  });

  test('after the close: the filed statement carries both, counted once',
      () async {
    final g = await buildGraph(DateTime(2026, 10, 26));
    final f = g.dashboard.nextMonthForecast;

    final filed = g.bills.allBills
        .where((b) => b.isAutoStatement && b.month == '2026-11')
        .toList();
    expect(filed, hasLength(1));
    // The generator charged the installment month into the statement...
    expect(filed.single.amount, closeTo(845.69 + 600, 0.005));
    // ...so the forecast takes the statement and adds no installment again.
    expect(f.bills, closeTo(845.69 + 600, 0.005));
    expect(f.installments, 0);
  });
}
