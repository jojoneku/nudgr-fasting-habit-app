// Capture Inbox page (Plan 070): the empty states, a row that still needs a
// field, and approve from the row. Presenter logic has its own suite; this
// checks the view renders what the presenter says and forwards the tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/capture_settings.dart';
import 'package:intermittent_fasting/models/finance/captured_transaction.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/raw_capture.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/capture_inbox_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/capture_bridge_service.dart';
import 'package:intermittent_fasting/views/treasury/capture/capture_inbox_view.dart';

import '../mocks.mocks.dart';

const _gcash = 'com.globe.gcash.android';

class _Bridge implements CaptureBridgeService {
  bool supported = true;
  bool granted = true;
  List<RawCapture> queue = [];
  @override
  bool get isSupported => supported;
  @override
  Future<bool> isAccessGranted() async => granted;
  @override
  Future<void> openAccessSettings() async {}
  @override
  Future<void> requestRebind() async {}
  @override
  Future<void> setAllowlist(
    Set<String> packages, {
    Map<String, List<String>> titleFilters = const {},
  }) async {}
  @override
  Future<List<RawCapture>> drainRaw() async {
    final out = queue;
    queue = [];
    return out;
  }

  @override
  Future<void> requeue(List<RawCapture> captures) async {}
  @override
  Future<List<RecentApp>> recentApps() async => const [];
  @override
  Future<DateTime?> lastConnectedAt() async => null;
}

RawCapture _raw(String text) => RawCapture(
      packageName: _gcash,
      appLabel: 'GCash',
      postedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      title: '',
      text: text,
      fingerprint: 'fp${text.hashCode}',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late _Bridge bridge;
  late CaptureSettings settings;
  late List<CapturedTransaction> inbox;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MockStorageService();
    stats = MockStatsPresenter();
    bridge = _Bridge();
    inbox = [];
    settings = const CaptureSettings(
      enabled: true,
      sources: {_gcash},
      accountBySource: {_gcash: 'gcash'},
    );
    when(stats.stats).thenReturn(UserStats.initial());
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'gcash',
            name: 'GCash',
            category: AccountCategory.ewallet,
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
            colorHex: '#000000',
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadCaptureInbox()).thenAnswer((_) async => inbox);
    when(storage.saveCaptureInbox(any)).thenAnswer((inv) async {
      inbox =
          List<CapturedTransaction>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadCaptureSettings()).thenAnswer((_) async => settings);
    when(storage.saveCaptureSettings(any)).thenAnswer((inv) async {
      settings = inv.positionalArguments.first as CaptureSettings;
    });
  });

  Future<(LedgerPresenter, CaptureInboxPresenter)> pump(
      WidgetTester tester) async {
    late LedgerPresenter ledger;
    late CaptureInboxPresenter presenter;
    await tester.runAsync(() async {
      ledger = LedgerPresenter(storage, stats);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      presenter = CaptureInboxPresenter(storage, ledger, bridge);
      await presenter.load();
    });
    await tester.pumpWidget(MaterialApp(
      home: CaptureInboxView(presenter: presenter),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (ledger, presenter);
  }

  testWidgets('capture off shows the turn-on empty state', (tester) async {
    settings = settings.copyWith(enabled: false);
    await pump(tester);
    expect(find.text('Capture is off'), findsOneWidget);
    expect(find.text('Turn on capture'), findsOneWidget);
  });

  testWidgets('no access shows the enable-access empty state', (tester) async {
    bridge.granted = false;
    await pump(tester);
    expect(find.text('Notification access needed'), findsOneWidget);
    expect(find.text('Enable notification access'), findsOneWidget);
  });

  testWidgets('nothing pending shows the quiet empty state', (tester) async {
    await pump(tester);
    expect(find.text('Nothing to review'), findsOneWidget);
  });

  testWidgets('a row missing a category disables Approve and names it',
      (tester) async {
    bridge.queue = [_raw('You have paid PHP 120.00 to ZZZ CORP.')];
    final (ledger, _) = await pump(tester);

    expect(find.text('ZZZ CORP'), findsOneWidget);
    expect(find.text('Pick category'), findsOneWidget);
    expect(find.text('Needs category'), findsOneWidget);
    final approve = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'));
    expect(approve.onPressed, isNull);
    expect(ledger.allTransactions, isEmpty);
  });

  testWidgets('a ready row approves from the button and leaves the list',
      (tester) async {
    bridge.queue = [_raw('You have paid PHP 120.00 to FOOD HUB.')];
    final (ledger, presenter) = await pump(tester);

    expect(find.text('FOOD HUB'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Approve all ready (1)'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(ledger.allTransactions, hasLength(1));
    expect(ledger.allTransactions.single.amount, 120.0);
    expect(presenter.pendingCount, 0);
    expect(find.text('Nothing to review'), findsOneWidget);
    expect(find.textContaining('Undo'), findsOneWidget);
  });
}
