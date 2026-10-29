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
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/utils/finance_entry_extraction.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/widgets/advisor_log_card.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

/// The ledger's cloud tier, reduced to the one-shot extractor.
class _Extractor implements AiCoachService {
  @override
  AiCoachTier get tier => AiCoachTier.cloud;

  @override
  bool get isAvailable => true;

  @override
  Future<ExtractionResult?> extractFinanceEntries({
    required String message,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required String Function(String categoryId) categoryNameFor,
    DateTime? now,
  }) async =>
      const ExtractionResult(entries: [
        ExtractedEntry(
          txn: ParsedTransaction(
            amount: 5000,
            type: TransactionType.outflow,
            accountId: 'bpi',
            categoryId: 'food',
            description: 'BPI card',
            descriptionIsClean: true,
          ),
        ),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'bpi',
            name: 'BPI',
            category: AccountCategory.bank,
            balance: 1000,
            colorHex: '#FFFFFF',
            icon: 'wallet',
          ),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'food',
            name: 'Food',
            type: CategoryType.expense,
            icon: 'tag',
            colorHex: '#FFFFFF',
          ),
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

  /// A ledger with a review card up, as after a routed message.
  Future<LedgerPresenter> ledgerWithCard(WidgetTester tester) async {
    late LedgerPresenter ledger;
    await tester.runAsync(() async {
      ledger = LedgerPresenter(storage, stats, cloudAi: _Extractor());
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await ledger.sendChatInput('paid 5000 bpi card');
    });
    expect(ledger.chatState.entries, hasLength(1));
    return ledger;
  }

  Future<void> pumpCard(WidgetTester tester, LedgerPresenter ledger,
      {VoidCallback? onAskNudgy}) {
    return tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdvisorLogCard(ledger: ledger, onAskNudgy: onAskNudgy),
        ),
      ),
    ));
  }

  final button = find.text('Not a log — ask Nudgy');

  testWidgets('the review card offers "ask Nudgy" and the tap reaches it',
      (tester) async {
    final ledger = await ledgerWithCard(tester);
    var taps = 0;
    await pumpCard(tester, ledger, onAskNudgy: () => taps++);

    expect(button, findsOneWidget);
    final size = tester.getSize(find.ancestor(
        of: button, matching: find.byWidgetPredicate((w) => w is TextButton)));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));

    await tester.tap(button);
    expect(taps, 1);
  });

  testWidgets('no callback, no button', (tester) async {
    final ledger = await ledgerWithCard(tester);
    await pumpCard(tester, ledger);

    expect(button, findsNothing);
  });
}
