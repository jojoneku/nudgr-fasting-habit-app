import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

/// Nudgy plans future months from [TreasuryDashboardPresenter
/// .recurringCommitments]. A series the user stopped long ago must drop out of
/// it: a hand-made June BPI statement marked recurring had Nudgy counting a
/// ₱10,128.26 bill every month into October.
void main() {
  late MockStorageService storage;
  late List<Bill> bills;
  late List<Receivable> receivables;

  final now = DateTime.now();
  String monthsAgo(int n) => toMonthKey(DateTime(now.year, now.month - n));

  Bill bill(String name, String month, double amount) => Bill(
        id: '$name-$month',
        name: name,
        billType: BillType.utility,
        amount: amount,
        dueDay: 4,
        month: month,
        categoryId: '',
        isRecurring: true,
        recurrenceType: RecurrenceType.monthly,
      );

  Receivable salary(String month) => Receivable(
        id: 'salary-$month',
        name: 'Salary',
        receivableType: ReceivableType.other,
        amount: 30000,
        month: month,
        categoryId: '',
        isRecurring: true,
        recurrenceType: RecurrenceType.monthly,
      );

  setUp(() {
    storage = MockStorageService();
    bills = [];
    receivables = [];
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => bills);
    when(storage.loadReceivables()).thenAnswer((_) async => receivables);
    when(storage.loadBudgets()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
  });

  Future<List<String>> names() async {
    final p = TreasuryDashboardPresenter(storage);
    await p.load();
    return [for (final c in p.recurringCommitments) c.name];
  }

  test('a series stopped months ago is not a commitment', () async {
    bills = [bill('BPI Credit Card statement', monthsAgo(4), 10128.26)];

    expect(await names(), isEmpty);
  });

  test('a running series counts, even before this month is generated',
      () async {
    bills = [
      bill('Internet', monthsAgo(0), 999), // this month's copy exists
      bill('Electricity', monthsAgo(1), 1600), // last month's is the latest
    ];

    expect(await names(), containsAll(['Internet', 'Electricity']));
  });

  test('stopped recurring income drops out too', () async {
    receivables = [salary(monthsAgo(3))];

    expect(await names(), isEmpty);

    receivables = [salary(monthsAgo(0))];
    expect(await names(), ['Salary']);
  });
}
