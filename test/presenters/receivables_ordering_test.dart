import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

/// How the Receivables list is ordered, and what happens when the user
/// rearranges it by hand.
const _month = '2026-03';

Receivable _receivable({
  required String id,
  String? name,
  DateTime? expectedDate,
  bool isReceived = false,
  int? sortIndex,
  String categoryId = '',
  String month = _month,
}) =>
    Receivable(
      id: id,
      name: name ?? 'Receivable $id',
      receivableType: ReceivableType.salary,
      amount: 200,
      expectedDate: expectedDate,
      month: month,
      categoryId: categoryId,
      isReceived: isReceived,
      sortIndex: sortIndex,
    );

FinanceCategory _category(String id, CategoryType type, String hex) =>
    FinanceCategory(
        id: id, name: id, type: type, colorHex: hex, icon: 'category');

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;

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

  Future<void> seed(List<Receivable> receivables) async {
    when(storage.loadReceivables()).thenAnswer((_) async => receivables);
    await presenter.load();
    await presenter.setMonth(_month);
  }

  group('automatic order', () {
    test('same-day entries read alphabetically, not by time of day', () async {
      // The reported symptom: five rows all labelled "exp Mar 4" in an order
      // nothing on screen explained. `expectedDate` carried the time the entry
      // was created, and the sort compared full timestamps — so the visible
      // order was keyed to an invisible value.
      await seed([
        _receivable(
            id: 'c', name: 'Chacha', expectedDate: DateTime(2026, 3, 4, 8, 5)),
        _receivable(
            id: 'a', name: 'Aya', expectedDate: DateTime(2026, 3, 4, 21, 40)),
        _receivable(
            id: 'b', name: 'Bea', expectedDate: DateTime(2026, 3, 4, 13, 12)),
      ]);

      expect(
          presenter.receivables.map((r) => r.name), ['Aya', 'Bea', 'Chacha']);
    });

    test('ASAP first, then by day, with received sunk to the bottom', () async {
      await seed([
        _receivable(id: 'late', expectedDate: DateTime(2026, 3, 28)),
        _receivable(
            id: 'done', expectedDate: DateTime(2026, 3, 2), isReceived: true),
        _receivable(id: 'asap'),
        _receivable(id: 'early', expectedDate: DateTime(2026, 3, 5)),
      ]);

      expect(presenter.receivables.map((r) => r.id),
          ['asap', 'early', 'late', 'done']);
      expect(presenter.pendingReceivables.map((r) => r.id),
          ['asap', 'early', 'late']);
      expect(presenter.receivedReceivables.map((r) => r.id), ['done']);
      expect(presenter.hasManualReceivableOrder, isFalse);
    });
  });

  group('manual order', () {
    test('a drag ranks every pending entry and persists it', () async {
      await seed([
        _receivable(id: 'a', expectedDate: DateTime(2026, 3, 1)),
        _receivable(id: 'b', expectedDate: DateTime(2026, 3, 2)),
        _receivable(id: 'c', expectedDate: DateTime(2026, 3, 3)),
      ]);

      // Drag the last row to the top — the grouping-by-who-owes-you move.
      await presenter.reorderPendingReceivables(2, 0);

      expect(presenter.pendingReceivables.map((r) => r.id), ['c', 'a', 'b']);
      expect(presenter.hasManualReceivableOrder, isTrue);
      // Ranks are total, so a later reload reproduces the arrangement rather
      // than re-deriving it from the dates.
      final saved = verify(storage.saveReceivables(captureAny)).captured.last
          as List<Receivable>;
      expect(
          {for (final r in saved) r.id: r.sortIndex}, {'c': 0, 'a': 1, 'b': 2});
    });

    test('survives a reload', () async {
      await seed([
        _receivable(id: 'a', expectedDate: DateTime(2026, 3, 1), sortIndex: 2),
        _receivable(id: 'b', expectedDate: DateTime(2026, 3, 2), sortIndex: 0),
        _receivable(id: 'c', expectedDate: DateTime(2026, 3, 3), sortIndex: 1),
      ]);

      expect(presenter.pendingReceivables.map((r) => r.id), ['b', 'c', 'a']);
    });

    test('a received entry still sinks below the arrangement', () async {
      await seed([
        _receivable(id: 'a', sortIndex: 1),
        _receivable(id: 'settled', sortIndex: 0, isReceived: true),
        _receivable(id: 'b', sortIndex: 2),
      ]);

      expect(presenter.receivables.map((r) => r.id), ['a', 'b', 'settled']);
    });

    test('an entry added afterwards lands after the ranked ones', () async {
      // No rank yet — appending is predictable, and beats silently reshuffling
      // the arrangement the user just made.
      await seed([
        _receivable(id: 'a', expectedDate: DateTime(2026, 3, 20), sortIndex: 0),
        _receivable(id: 'b', expectedDate: DateTime(2026, 3, 21), sortIndex: 1),
      ]);
      await presenter.addReceivable(
          _receivable(id: 'new', expectedDate: DateTime(2026, 3, 1)));

      expect(presenter.pendingReceivables.map((r) => r.id), ['a', 'b', 'new']);
    });

    test('a no-op drag changes nothing', () async {
      await seed([
        _receivable(id: 'a', expectedDate: DateTime(2026, 3, 1)),
        _receivable(id: 'b', expectedDate: DateTime(2026, 3, 2)),
      ]);
      clearInteractions(storage);

      await presenter.reorderPendingReceivables(1, 1);

      expect(presenter.hasManualReceivableOrder, isFalse);
      verifyNever(storage.saveReceivables(any));
    });

    test('reset drops the arrangement back to expected-date order', () async {
      await seed([
        _receivable(id: 'a', expectedDate: DateTime(2026, 3, 1), sortIndex: 2),
        _receivable(id: 'b', expectedDate: DateTime(2026, 3, 2), sortIndex: 0),
        _receivable(id: 'other', month: '2026-04', sortIndex: 5),
      ]);

      await presenter.resetReceivableOrder();

      expect(presenter.pendingReceivables.map((r) => r.id), ['a', 'b']);
      expect(presenter.hasManualReceivableOrder, isFalse);
      // Only the month on screen is reset — another month's arrangement stands.
      final saved = verify(storage.saveReceivables(captureAny)).captured.last
          as List<Receivable>;
      expect(saved.firstWhere((r) => r.id == 'other').sortIndex, 5);
    });
  });

  group('categoryPaletteSlot', () {
    test('is keyed to the category, not to a row position', () async {
      // The fallback slot `resolveSliceColor` uses when a category still carries
      // the legacy near-white color. Cards used to pass their list index, so two
      // rows sharing a category drew different colors and every color moved when
      // the list re-sorted.
      when(storage.loadFinanceCategories()).thenAnswer((_) async => [
            _category('salary', CategoryType.income, '#46BD6B'),
            _category('rent', CategoryType.expense, '#F6685E'),
            _category('refunds', CategoryType.income, '#26C6DA'),
          ]);
      await seed([]);
      await ledger.load();
      while (ledger.isLoading) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      expect(ledger.categories, hasLength(3));

      // Position within the same *type*, mirroring what `categoryColorAt` hands
      // a category at creation.
      expect(presenter.categoryPaletteSlot('salary'), 0);
      expect(presenter.categoryPaletteSlot('refunds'), 1);
      expect(presenter.categoryPaletteSlot('rent'), 0);
      // Unknown / unset category: slot 0, and the card supplies its own fallback
      // color anyway.
      expect(presenter.categoryPaletteSlot(''), 0);
    });
  });

  group('serialisation', () {
    test('sortIndex survives a JSON roundtrip and can be cleared', () {
      final ranked = _receivable(id: 'a', sortIndex: 3);
      expect(Receivable.fromJson(ranked.toJson()).sortIndex, 3);
      // Omitted → kept; explicit null → back to automatic ordering.
      expect(ranked.copyWith(name: 'renamed').sortIndex, 3);
      expect(ranked.copyWith(sortIndex: null).sortIndex, isNull);
      expect(Receivable.fromJson({'id': 'x'}).sortIndex, isNull);
    });
  });
}
