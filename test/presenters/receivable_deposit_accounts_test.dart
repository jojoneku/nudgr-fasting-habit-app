import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

/// Which accounts a receivable can be deposited into, and which one is
/// preselected. Both platforms had drifted: web offered only `isLiquid`
/// (bank/ewallet/cash), so a salary landing in savings could not be recorded
/// there; mobile offered every account, archived ones and credit cards
/// included. See docs/receivable_destination_account_spec.md.
FinancialAccount _account(
  String id,
  AccountCategory category, {
  bool isActive = true,
}) =>
    FinancialAccount(
      id: id,
      name: id,
      category: category,
      balance: 1000,
      colorHex: '#FFFFFF',
      icon: 'wallet',
      isActive: isActive,
    );

Receivable _receivable({String? accountId}) => Receivable(
      id: 'r1',
      name: 'Reimbursement',
      receivableType: ReceivableType.reimbursement,
      amount: 500,
      month: '2026-03',
      categoryId: '',
      accountId: accountId,
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;

  Future<void> seedAccounts(List<FinancialAccount> accounts) async {
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    await ledger.load();
  }

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
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
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
    presenter = BillsReceivablesPresenter(storage, ledger, stats);
  });

  group('depositAccountsFor', () {
    test('offers every active asset account, savings and goals included',
        () async {
      await seedAccounts([
        _account('bank', AccountCategory.bank),
        _account('savings', AccountCategory.savings),
        _account('goal', AccountCategory.goal),
        _account('cash', AccountCategory.cash),
      ]);

      expect(
        presenter.depositAccountsFor(_receivable()).map((a) => a.id),
        ['bank', 'savings', 'goal', 'cash'],
      );
    });

    test('excludes liability accounts', () async {
      // markReceivableReceived posts a plain inflow, so crediting a card would
      // record income against it instead of paying it down.
      await seedAccounts([
        _account('bank', AccountCategory.bank),
        _account('visa', AccountCategory.creditCard),
        _account('bnpl', AccountCategory.bnpl),
        _account('line', AccountCategory.creditLine),
      ]);

      expect(
        presenter.depositAccountsFor(_receivable()).map((a) => a.id),
        ['bank'],
      );
    });

    test('excludes archived accounts', () async {
      await seedAccounts([
        _account('bank', AccountCategory.bank),
        _account('old', AccountCategory.bank, isActive: false),
      ]);

      expect(
        presenter.depositAccountsFor(_receivable()).map((a) => a.id),
        ['bank'],
      );
    });

    test('is empty when only liabilities exist', () async {
      await seedAccounts([_account('visa', AccountCategory.creditCard)]);

      expect(presenter.depositAccountsFor(_receivable()), isEmpty);
    });
  });

  group('preferredDepositAccountId', () {
    test('prefers the receivable\'s saved account when still eligible',
        () async {
      await seedAccounts([
        _account('bank', AccountCategory.bank),
        _account('savings', AccountCategory.savings),
      ]);

      expect(
        presenter.preferredDepositAccountId(_receivable(accountId: 'savings')),
        'savings',
      );
    });

    test('falls back to the first liquid account, not merely the first',
        () async {
      // Keeps the default users see today even though savings is now selectable.
      await seedAccounts([
        _account('savings', AccountCategory.savings),
        _account('bank', AccountCategory.bank),
      ]);

      expect(presenter.preferredDepositAccountId(_receivable()), 'bank');
    });

    test('falls back to the first eligible when nothing is liquid', () async {
      await seedAccounts([
        _account('savings', AccountCategory.savings),
        _account('goal', AccountCategory.goal),
      ]);

      expect(presenter.preferredDepositAccountId(_receivable()), 'savings');
    });

    test('ignores a saved account that is archived', () async {
      await seedAccounts([
        _account('old', AccountCategory.bank, isActive: false),
        _account('bank', AccountCategory.bank),
      ]);

      expect(
        presenter.preferredDepositAccountId(_receivable(accountId: 'old')),
        'bank',
      );
    });

    test('ignores a saved liability — reachable from the old mobile picker',
        () async {
      await seedAccounts([
        _account('visa', AccountCategory.creditCard),
        _account('bank', AccountCategory.bank),
      ]);

      expect(
        presenter.preferredDepositAccountId(_receivable(accountId: 'visa')),
        'bank',
      );
    });

    test('is null when there is nothing to deposit into', () async {
      await seedAccounts([_account('visa', AccountCategory.creditCard)]);

      expect(presenter.preferredDepositAccountId(_receivable()), isNull);
    });

    test('handles a null receivable (the add-form default picker)', () async {
      await seedAccounts([_account('bank', AccountCategory.bank)]);

      expect(presenter.preferredDepositAccountId(null), 'bank');
    });
  });
}
