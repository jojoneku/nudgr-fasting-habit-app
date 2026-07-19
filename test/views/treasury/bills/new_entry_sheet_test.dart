import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/new_entry_sheet.dart';
import '../../../mocks.mocks.dart';

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late InstallmentPresenter installments;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    presenter = BillsReceivablesPresenter(storage, ledger, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
  });

  Widget host() => MaterialApp(
        home: Scaffold(
          body: NewEntrySheet(
            presenter: presenter,
            installmentPresenter: installments,
          ),
        ),
      );

  testWidgets('type selector swaps the embedded form', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text('New entry'), findsOneWidget);
    // Defaults to the bill form.
    expect(find.text('Save bill'), findsOneWidget);

    await tester.tap(find.text('Receivable'));
    await tester.pumpAndSettle();
    expect(find.text('Save receivable'), findsOneWidget);
    expect(find.text('Save bill'), findsNothing);

    // On the receivable form the bill-type chips are gone, so "Installment" is
    // now unambiguous (only the type-selector chip).
    await tester.tap(find.text('Installment'));
    await tester.pumpAndSettle();
    expect(find.text('Add Installment'), findsWidgets);

    await tester.tap(find.text('Set-aside'));
    await tester.pumpAndSettle();
    expect(find.text('Add Expense'), findsOneWidget);
  });
}
