import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_setup_view.dart';
import '../mocks.mocks.dart';

/// Audit #4: editing a sub-account (pocket) opened without an explicit
/// `parentAccountId` — e.g. from the dashboard Goals section — must NOT detach
/// it from its parent. Previously the mobile form wrote
/// `parentAccountId: widget.parentAccountId` (null), orphaning the pocket while
/// the parent's balance still counted it (double-counted net worth).
void main() {
  late MockStorageService mockStorage;

  final parentBank = FinancialAccount(
    id: 'bank1',
    name: 'Main Bank',
    category: AccountCategory.bank,
    balance: 20000,
    colorHex: '#2563EB',
    icon: 'bank',
  );
  final pocket = FinancialAccount(
    id: 'p1',
    name: 'Emergency Fund',
    category: AccountCategory.savings,
    parentAccountId: 'bank1',
    balance: 5000,
    colorHex: '#059669',
    icon: 'savings',
  );

  setUp(() {
    mockStorage = MockStorageService();
    when(mockStorage.loadAccounts())
        .thenAnswer((_) async => [parentBank, pocket]);
    when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
    when(mockStorage.loadBills()).thenAnswer((_) async => []);
    when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(mockStorage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
  });

  testWidgets(
      'saving a pocket opened without parentAccountId preserves its parent',
      (tester) async {
    final presenter = TreasuryDashboardPresenter(mockStorage);
    await presenter.load();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountSetupView(
          presenter: presenter,
          existing: pocket,
          // Opened from a context that doesn't thread the parent through.
          parentAccountId: null,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final captured = verify(mockStorage.saveAccounts(captureAny)).captured.last
        as List<FinancialAccount>;
    final saved = captured.firstWhere((a) => a.id == 'p1');
    expect(saved.parentAccountId, 'bank1',
        reason: 'pocket must stay attached to its parent after an edit');
  });
}
