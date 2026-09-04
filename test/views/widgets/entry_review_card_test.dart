import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/extracted_entry.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/widgets/finance/entry_review_card.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

FinancialAccount _acc(String id, String name) => FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.bank,
      balance: 1000,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name, CategoryType type) =>
    FinanceCategory(
      id: id,
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

ExtractedEntry _entry({
  double? amount = 175,
  String? accountId = 'gcash',
  String? categoryId = 'food',
  String description = 'Avocado Ice Cream',
  Set<EntryField> missing = const {},
  double confidence = 0.9,
  DateTime? date,
}) =>
    ExtractedEntry(
      txn: ParsedTransaction(
        amount: amount,
        type: TransactionType.outflow,
        accountId: accountId,
        categoryId: categoryId,
        description: description,
        descriptionIsClean: true,
        date: date,
      ),
      missing: missing,
      confidence: confidence,
    );

/// The card's commit button. Found by predicate, not by type: FilledButton.icon
/// builds a private subclass that find.byType/widgetWithText will not match.
FilledButton _commitButton(WidgetTester tester) => tester
    .widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts())
        .thenAnswer((_) async => [_acc('gcash', 'GCash'), _acc('bpi', 'BPI')]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          _cat('food', 'Food', CategoryType.expense),
          _cat('salary', 'Salary', CategoryType.income),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  });

  /// Builds a loaded presenter. The wait runs inside [WidgetTester.runAsync]
  /// because a widget test drives a fake clock — a bare Future.delayed loop
  /// never advances there and hangs the test.
  Future<LedgerPresenter> presenter(WidgetTester tester) async {
    late LedgerPresenter p;
    await tester.runAsync(() async {
      p = LedgerPresenter(storage, stats);
      while (p.isLoading) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
    });
    return p;
  }

  /// Seeds the real presenter and renders the card off its state, so the
  /// interaction tests exercise the same path the app does.
  Future<void> pump(
    WidgetTester tester,
    LedgerPresenter p,
    List<ExtractedEntry> entries,
  ) async {
    p.debugSeedReview(entries);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: p,
            builder: (_, __) => EntryReviewCard(ledger: p, state: p.chatState),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders one row per entry with its description and amount',
      (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [
      _entry(amount: 175, description: 'Personal Shopping'),
      _entry(amount: 115, description: 'Avocado Ice Cream'),
    ]);

    expect(find.textContaining('2 entries'), findsOneWidget);
    expect(find.text('Personal Shopping'), findsOneWidget);
    expect(find.text('Avocado Ice Cream'), findsOneWidget);
    expect(find.text('₱175'), findsOneWidget);
    expect(find.text('₱115'), findsOneWidget);
  });

  testWidgets('a resolved entry shows its account and category',
      (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [_entry()]);

    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('a missing account shows a prompt chip instead of a name',
      (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [
      _entry(accountId: null, missing: {EntryField.account}),
    ]);

    expect(find.text('Add account'), findsOneWidget);
    expect(find.textContaining('Tap the lit chip'), findsOneWidget);
  });

  testWidgets('Log all is disabled while any row has a gap', (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [
      _entry(amount: 175),
      _entry(amount: 90, accountId: null, missing: {EntryField.account}),
    ]);

    expect(_commitButton(tester).onPressed, isNull,
        reason: 'partial logging behind the user is what this change ends');
  });

  testWidgets('Log all is enabled once every row is complete', (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [_entry(amount: 175), _entry(amount: 90)]);

    expect(_commitButton(tester).onPressed, isNotNull);
  });

  testWidgets('a single entry offers "Log it", not "Log all"', (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [_entry()]);

    expect(find.text('Log it'), findsOneWidget);
    expect(find.textContaining('Log all'), findsNothing);
    expect(find.text('1 entries'), findsNothing);
  });

  testWidgets('a low-confidence row asks to be checked', (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [_entry(confidence: 0.3)]);

    expect(find.text('Check this'), findsOneWidget);
  });

  testWidgets('an undated row reads Today, not a date it does not have',
      (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [_entry(date: null)]);

    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('a back-dated row names the day', (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [
      _entry(date: DateTime.now().subtract(const Duration(days: 1))),
    ]);

    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets('tapping an account chip picks a real account inline',
      (tester) async {
    final p = await presenter(tester);
    // Seed the presenter so the picker's callback has something to update.
    await pump(tester, p, [
      _entry(accountId: null, missing: {EntryField.account}),
    ]);

    await tester.tap(find.text('Add account'));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget, reason: 'the picker sheet');
    await tester.tap(find.text('BPI').last);
    await tester.pumpAndSettle();

    expect(p.chatState.entries.single.txn.accountId, 'bpi');
    expect(p.chatState.entries.single.missing, isEmpty);
  });

  testWidgets('the remove button only appears on multi-entry messages',
      (tester) async {
    final p = await presenter(tester);
    await pump(tester, p, [_entry()]);
    expect(find.byTooltip('Remove this entry'), findsNothing);

    await pump(tester, p, [_entry(amount: 175), _entry(amount: 90)]);
    expect(find.byTooltip('Remove this entry'), findsNWidgets(2));
  });
}
