import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

/// Audit: installment completion (+50) and all-due-paid (+20) XP were
/// re-awardable via markUnpaid/markPaid cycles. A persisted award-key guard
/// now grants each at most once.
void main() {
  late MockStorageService mockStorage;
  late MockStatsPresenter mockStats;
  late LedgerPresenter ledger;
  late InstallmentPresenter presenter;

  Installment oneMonth() => Installment(
        id: 'i1',
        name: 'MacBook',
        accountId: 'cc',
        totalAmount: 1000,
        monthlyAmount: 1000,
        totalMonths: 1,
        startMonth: '2026-03',
      );

  Future<void> waitForLedger() async {
    while (ledger.isLoading) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    mockStorage = MockStorageService();
    mockStats = MockStatsPresenter();
    when(mockStorage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'cc',
            name: 'Card',
            category: AccountCategory.creditCard,
            balance: 0,
            colorHex: '#FFFFFF',
            icon: 'card',
          ),
        ]);
    when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(mockStorage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(mockStorage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(mockStorage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(mockStorage.saveTransactions(any)).thenAnswer((_) async {});
    when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
    when(mockStorage.loadInstallments()).thenAnswer((_) async => [oneMonth()]);
    when(mockStorage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(mockStorage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.awardStat(any)).thenAnswer((_) async {});
    when(mockStats.stats).thenReturn(UserStats.initial());

    ledger = LedgerPresenter(mockStorage, mockStats);
    presenter = InstallmentPresenter(mockStorage, ledger, mockStats);
  });

  test('completion (+50) and all-due (+20) are awarded once on first pay',
      () async {
    await presenter.load();
    await waitForLedger();
    presenter.setMonth('2026-03');

    await presenter.markPaid('i1');

    verify(mockStats.addXp(50)).called(1);
    verify(mockStats.addXp(20)).called(1);
  });

  test('unpay + re-pay does not re-award the installment XP (audit)', () async {
    await presenter.load();
    await waitForLedger();
    presenter.setMonth('2026-03');

    await presenter.markPaid('i1'); // +50 completion, +20 all-due
    await presenter.markUnpaid('i1');
    await presenter.markPaid('i1'); // must NOT re-award either

    verify(mockStats.addXp(50)).called(1);
    verify(mockStats.addXp(20)).called(1);
  });

  test('award is not re-granted after restart (persisted guard)', () async {
    when(mockStorage.loadAwardedXpKeys()).thenAnswer((_) async => {
          'installment.complete/i1',
          'installment.allDuePaid/2026-03',
        });
    // Rebuild so the presenter loads the persisted guard set.
    ledger = LedgerPresenter(mockStorage, mockStats);
    presenter = InstallmentPresenter(mockStorage, ledger, mockStats);
    await presenter.load();
    await waitForLedger();
    presenter.setMonth('2026-03');

    await presenter.markPaid('i1');

    verifyNever(mockStats.addXp(50));
    verifyNever(mockStats.addXp(20));
  });
}
