// Capture Inbox (Plan 070): drain → pending rows, approve → one ledger record
// with one balance move, decline → tombstone that dedupes, undo both ways,
// retention purge, and the settings → native allowlist contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/capture_settings.dart';
import 'package:intermittent_fasting/models/finance/captured_transaction.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/raw_capture.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/capture_inbox_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/capture_bridge_service.dart';
import 'package:intermittent_fasting/utils/capture_templates.dart';

import '../mocks.mocks.dart';

const _gcash = 'com.globe.gcash.android';
const _maya = 'com.paymaya';

/// In-memory stand-in for the Android listener.
class FakeCaptureBridge implements CaptureBridgeService {
  bool supported = true;
  bool granted = true;
  DateTime? connectedAt;
  List<RawCapture> queue = [];
  Set<String>? lastAllowlist;
  Map<String, List<String>>? lastTitleFilters;
  int drainCalls = 0;
  int rebinds = 0;
  int settingsOpens = 0;

  @override
  bool get isSupported => supported;
  @override
  Future<bool> isAccessGranted() async => granted;
  @override
  Future<void> openAccessSettings() async => settingsOpens++;
  @override
  Future<void> requestRebind() async => rebinds++;
  @override
  Future<void> setAllowlist(
    Set<String> packages, {
    Map<String, List<String>> titleFilters = const {},
  }) async {
    lastAllowlist = packages;
    lastTitleFilters = titleFilters;
  }

  @override
  Future<List<RawCapture>> drainRaw() async {
    drainCalls++;
    final out = queue;
    queue = [];
    return out;
  }

  @override
  Future<void> requeue(List<RawCapture> captures) async =>
      queue = [...captures, ...queue];
  @override
  Future<List<RecentApp>> recentApps() async => const [];
  @override
  Future<DateTime?> lastConnectedAt() async => connectedAt;
}

FinancialAccount _acc(String id, String name, double balance) =>
    FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.ewallet,
      balance: balance,
      colorHex: '#000000',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name) => FinanceCategory(
      id: id,
      name: name,
      type: CategoryType.expense,
      icon: 'tag',
      colorHex: '#000000',
    );

RawCapture _raw(String pkg, String text, {DateTime? at, String? fp}) =>
    RawCapture(
      packageName: pkg,
      appLabel: pkg == _gcash ? 'GCash' : 'Maya',
      postedAt: at ?? DateTime(2026, 11, 2, 12),
      title: '',
      text: text,
      fingerprint: fp ?? 'fp${text.hashCode}',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late FakeCaptureBridge bridge;
  late List<TransactionRecord> storedTxns;
  late List<FinancialAccount> storedAccounts;
  late List<CapturedTransaction> storedInbox;
  late CaptureSettings storedSettings;
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 2, 14);
    storage = MockStorageService();
    stats = MockStatsPresenter();
    bridge = FakeCaptureBridge();
    storedTxns = [];
    storedAccounts = [_acc('gcash', 'GCash', 1000), _acc('maya', 'Maya', 500)];
    storedInbox = [];
    storedSettings = const CaptureSettings(
      enabled: true,
      sources: {_gcash, _maya},
      accountBySource: {_gcash: 'gcash', _maya: 'maya'},
    );

    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => const NotificationPreferences());
    when(storage.loadAccounts()).thenAnswer((_) async => storedAccounts);
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      storedAccounts =
          List<FinancialAccount>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => [_cat('food', 'Food'), _cat('misc', 'Misc')]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => storedTxns);
    when(storage.saveTransactions(any)).thenAnswer((inv) async {
      storedTxns =
          List<TransactionRecord>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadCaptureInbox()).thenAnswer((_) async => storedInbox);
    when(storage.saveCaptureInbox(any)).thenAnswer((inv) async {
      storedInbox =
          List<CapturedTransaction>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadCaptureSettings()).thenAnswer((_) async => storedSettings);
    when(storage.saveCaptureSettings(any)).thenAnswer((inv) async {
      storedSettings = inv.positionalArguments.first as CaptureSettings;
    });
  });

  Future<(LedgerPresenter, CaptureInboxPresenter)> build() async {
    final ledger = LedgerPresenter(storage, stats, clock: clock);
    await ledger.load();
    final inbox = CaptureInboxPresenter(storage, ledger, bridge, clock: clock);
    await inbox.load();
    return (ledger, inbox);
  }

  double balanceOf(LedgerPresenter l, String id) =>
      l.accounts.firstWhere((a) => a.id == id).balance;

  group('twins across sources', () {
    test('a later row repeating an earlier one within 15 min is its twin',
        () async {
      bridge.queue = [
        _raw(_gcash, 'You have paid PHP 100.00 to FOOD HUB.',
            at: DateTime(2026, 11, 2, 12, 0)),
        _raw(_maya, 'You paid PHP 100.00 to FOOD HUB.',
            at: DateTime(2026, 11, 2, 12, 1)),
      ];
      final (_, inbox) = await build();
      expect(inbox.pendingCount, 2);
      final later = inbox.pending.first; // newest first
      final earlier = inbox.pending.last;
      expect(later.sourceApp, _maya);
      expect(inbox.twinOf(later)?.id, earlier.id);
      expect(inbox.twinOf(earlier), isNull);
    });

    test('approve posts once and declines the twin; undo restores both',
        () async {
      bridge.queue = [
        _raw(_gcash, 'You have paid PHP 100.00 to FOOD HUB.',
            at: DateTime(2026, 11, 2, 12, 0)),
        _raw(_maya, 'You paid PHP 100.00 to FOOD HUB.',
            at: DateTime(2026, 11, 2, 12, 1)),
      ];
      final (ledger, inbox) = await build();
      final earlier = inbox.pending.last;
      await inbox.approve(earlier.id);
      expect(ledger.allTransactions, hasLength(1));
      expect(inbox.pendingCount, 0);
      expect(inbox.lastAutoDeclinedLabels, ['Maya']);
      expect(balanceOf(ledger, 'gcash'), 900);
      expect(balanceOf(ledger, 'maya'), 500);

      await inbox.undo(earlier.id);
      expect(ledger.allTransactions, isEmpty);
      expect(inbox.pendingCount, 2);
    });

    test('a different amount or a far-apart time is not a twin', () async {
      bridge.queue = [
        _raw(_gcash, 'You have paid PHP 100.00 to FOOD HUB.',
            at: DateTime(2026, 11, 2, 12, 0)),
        _raw(_maya, 'You paid PHP 120.00 to FOOD HUB.',
            at: DateTime(2026, 11, 2, 12, 1)),
        _raw(_maya, 'You paid PHP 100.00 to FOOD HUB.',
            at: DateTime(2026, 11, 2, 13, 0)),
      ];
      final (_, inbox) = await build();
      expect(inbox.pending.every((c) => inbox.twinOf(c) == null), isTrue);
    });
  });

  group('sender-filtered sources', () {
    test('turning Gmail on seeds the BPI sender filter and pushes it native',
        () async {
      final (_, inbox) = await build();
      await inbox.setSourceEnabled(kGmailPackage, 'Gmail', true);
      expect(inbox.settings.senderFilters[kGmailPackage], ['BPI']);
      expect(bridge.lastAllowlist, contains(kGmailPackage));
      expect(bridge.lastTitleFilters?[kGmailPackage], ['BPI']);
    });

    test('a source without a filter pushes none', () async {
      final (_, inbox) = await build();
      await inbox.setSourceEnabled('com.example.bank', 'Bank', true);
      expect(bridge.lastTitleFilters?.containsKey('com.example.bank'), isFalse);
    });
  });

  group('load + drain', () {
    test('load re-asserts the allowlist and drains the native queue', () async {
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.')];
      final (_, inbox) = await build();

      expect(bridge.lastAllowlist, {_gcash, _maya});
      expect(bridge.drainCalls, 1);
      expect(inbox.pendingCount, 1);
      final row = inbox.pending.single;
      expect(row.draft.amount, 120.0);
      expect(row.draft.accountId, 'gcash');
      expect(row.draft.categoryId, 'food');
      expect(row.isReady, isTrue);
      expect(inbox.readyCount, 1);
      expect(inbox.lastCaptureAt, row.capturedAt);
      verify(storage.saveCaptureInbox(any)).called(greaterThan(0));
    });

    test('a capture from a non-allowlisted app is dropped', () async {
      bridge.queue = [_raw('com.other.app', 'You paid PHP 50.00 to X.')];
      final (_, inbox) = await build();
      expect(inbox.pendingCount, 0);
    });

    test('the same fingerprint is filed once', () async {
      bridge.queue = [
        _raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.', fp: 'same'),
        _raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.', fp: 'same'),
      ];
      final (_, inbox) = await build();
      expect(inbox.pendingCount, 1);
      bridge.queue = [
        _raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.', fp: 'same')
      ];
      expect(await inbox.drain(), 0);
      expect(inbox.pendingCount, 1);
    });

    test('capture off: nothing is drained and the allowlist is emptied',
        () async {
      storedSettings = storedSettings.copyWith(enabled: false);
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.')];
      final (_, inbox) = await build();
      expect(bridge.drainCalls, 0);
      expect(bridge.lastAllowlist, isEmpty);
      expect(inbox.pendingCount, 0);
    });

    test('unsupported platform never touches the bridge', () async {
      bridge.supported = false;
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.')];
      final (_, inbox) = await build();
      expect(bridge.drainCalls, 0);
      expect(bridge.lastAllowlist, isNull);
      expect(inbox.isSupported, isFalse);
    });

    test('a failed persist requeues the captures', () async {
      when(storage.saveCaptureInbox(any)).thenThrow(Exception('disk full'));
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.')];
      final (_, inbox) = await build();
      expect(inbox.pendingCount, 0);
      expect(bridge.queue, hasLength(1));
    });
  });

  group('approve', () {
    test('posts one ledger record and moves the balance once', () async {
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.')];
      final (ledger, inbox) = await build();
      final id = inbox.pending.single.id;

      final posted = await inbox.approve(id);

      expect(posted, isNotNull);
      expect(ledger.allTransactions, hasLength(1));
      expect(ledger.allTransactions.single.amount, 120.0);
      expect(ledger.allTransactions.single.type, TransactionType.outflow);
      expect(ledger.allTransactions.single.description, 'FOOD HUB');
      expect(balanceOf(ledger, 'gcash'), 880.0);
      expect(inbox.pendingCount, 0);
      final row = inbox.byId(id)!;
      expect(row.status, CaptureStatus.approved);
      expect(row.transactionId, posted!.id);
      expect(row.resolvedAt, now);
      expect(inbox.recentlyResolved.single.id, id);
    });

    test('a row missing a field refuses to post', () async {
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to ZZZ CORP.')];
      final (ledger, inbox) = await build();
      final row = inbox.pending.single;
      expect(row.isReady, isFalse); // no category for ZZZ CORP

      await expectLater(inbox.approve(row.id), throwsStateError);
      expect(ledger.allTransactions, isEmpty);
      expect(inbox.pendingCount, 1);
    });

    test('supplying the missing chip makes it ready; approve all posts it',
        () async {
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to ZZZ CORP.')];
      final (ledger, inbox) = await build();
      final row = inbox.pending.single;

      await inbox.setDraft(row.id, row.draft.copyWith(categoryId: 'misc'));
      expect(inbox.readyCount, 1);
      expect(await inbox.approveAllReady(), 1);
      expect(ledger.allTransactions.single.categoryId, 'misc');
      expect(inbox.pendingCount, 0);
    });

    test('a transfer between own accounts posts two legs in one group',
        () async {
      bridge.queue = [_raw(_maya, 'You sent PHP 300.00 to GCash. Ref 1.')];
      final (ledger, inbox) = await build();
      final row = inbox.pending.single;
      expect(row.draft.type, TransactionType.transfer);

      await inbox.approve(row.id);

      expect(ledger.allTransactions, hasLength(2));
      final group = ledger.allTransactions.first.transferGroupId;
      expect(group, isNotNull);
      expect(ledger.allTransactions.every((t) => t.transferGroupId == group),
          isTrue);
      expect(balanceOf(ledger, 'maya'), 200.0);
      expect(balanceOf(ledger, 'gcash'), 1300.0);
    });

    test('undo of an approve deletes the record and restores the row',
        () async {
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.')];
      final (ledger, inbox) = await build();
      final id = inbox.pending.single.id;
      await inbox.approve(id);
      expect(balanceOf(ledger, 'gcash'), 880.0);

      await inbox.undo(id);

      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'gcash'), 1000.0);
      expect(inbox.byId(id)!.status, CaptureStatus.pending);
      expect(inbox.byId(id)!.transactionId, isNull);
    });

    test('undo of a transfer removes both legs', () async {
      bridge.queue = [_raw(_maya, 'You sent PHP 300.00 to GCash. Ref 1.')];
      final (ledger, inbox) = await build();
      final id = inbox.pending.single.id;
      await inbox.approve(id);
      await inbox.undo(id);
      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'maya'), 500.0);
      expect(balanceOf(ledger, 'gcash'), 1000.0);
    });

    test('flags a possible duplicate the user logged by hand', () async {
      storedTxns = [
        TransactionRecord(
          id: 'manual',
          date: DateTime(2026, 11, 2, 11, 50),
          accountId: 'gcash',
          categoryId: 'food',
          amount: 120,
          type: TransactionType.outflow,
          description: 'lunch',
          month: '2026-11',
        ),
      ];
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.')];
      final (_, inbox) = await build();
      expect(inbox.isPossibleDuplicate(inbox.pending.single), isTrue);
    });
  });

  group('decline', () {
    test('decline keeps a tombstone that dedupes a re-post', () async {
      bridge.queue = [
        _raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.', fp: 'again')
      ];
      final (ledger, inbox) = await build();
      final id = inbox.pending.single.id;

      await inbox.decline(id);
      expect(inbox.pendingCount, 0);
      expect(ledger.allTransactions, isEmpty);
      expect(inbox.byId(id)!.status, CaptureStatus.declined);

      bridge.queue = [
        _raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.', fp: 'again')
      ];
      expect(await inbox.drain(), 0);
      expect(inbox.pendingCount, 0);
    });

    test('undo of a decline brings the row back', () async {
      bridge.queue = [_raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.')];
      final (_, inbox) = await build();
      final id = inbox.pending.single.id;
      await inbox.decline(id);
      await inbox.undo(id);
      expect(inbox.pendingCount, 1);
    });

    test('declineAll clears every pending row', () async {
      bridge.queue = [
        _raw(_gcash, 'You have paid PHP 120.00 to FOOD HUB.', fp: 'a'),
        _raw(_maya, 'You paid PHP 80.00 to STORE.', fp: 'b'),
      ];
      final (_, inbox) = await build();
      expect(await inbox.declineAll(), 2);
      expect(inbox.pendingCount, 0);
    });
  });

  group('retention', () {
    test('old declined and approved rows are purged on load', () async {
      CapturedTransaction row(String id, CaptureStatus s, DateTime at) =>
          CapturedTransaction(
            id: id,
            source: CaptureSource.androidNotification,
            sourceApp: _gcash,
            sourceLabel: 'GCash',
            capturedAt: at,
            rawTitle: '',
            rawText: 'x',
            fingerprint: id,
            draft: const ParsedTransaction(),
            status: s,
            resolvedAt: at,
          );
      storedInbox = [
        row('old-declined', CaptureStatus.declined,
            now.subtract(const Duration(days: 31))),
        row('fresh-declined', CaptureStatus.declined,
            now.subtract(const Duration(days: 29))),
        row('old-approved', CaptureStatus.approved,
            now.subtract(const Duration(days: 8))),
        row('fresh-approved', CaptureStatus.approved,
            now.subtract(const Duration(days: 6))),
      ];
      final (_, inbox) = await build();
      expect(inbox.byId('old-declined'), isNull);
      expect(inbox.byId('fresh-declined'), isNotNull);
      expect(inbox.byId('old-approved'), isNull);
      expect(inbox.byId('fresh-approved'), isNotNull);
    });
  });

  group('settings', () {
    test('enabling with no sources seeds the presets and pushes them native',
        () async {
      storedSettings = const CaptureSettings();
      final (_, inbox) = await build();
      expect(inbox.isEnabled, isFalse);

      await inbox.setEnabled(true);

      expect(inbox.isEnabled, isTrue);
      expect(inbox.settings.sources, contains(_gcash));
      expect(bridge.lastAllowlist, inbox.settings.sources);
      expect(storedSettings.enabled, isTrue);
    });

    test('disabling empties the native allowlist but keeps the list', () async {
      final (_, inbox) = await build();
      await inbox.setEnabled(false);
      expect(bridge.lastAllowlist, isEmpty);
      expect(inbox.settings.sources, {_gcash, _maya});
    });

    test('source toggles and account maps persist', () async {
      final (_, inbox) = await build();
      await inbox.setSourceEnabled('com.new.bank', 'New Bank', true);
      await inbox.setSourceAccount('com.new.bank', 'maya');
      await inbox.setLast4Account('1234', 'gcash');
      expect(storedSettings.sources, contains('com.new.bank'));
      expect(storedSettings.labelFor('com.new.bank'), 'New Bank');
      expect(storedSettings.accountBySource['com.new.bank'], 'maya');
      expect(storedSettings.accountByLast4['1234'], 'gcash');
      expect(bridge.lastAllowlist, contains('com.new.bank'));
      await inbox.setSourceEnabled('com.new.bank', 'New Bank', false);
      expect(bridge.lastAllowlist, isNot(contains('com.new.bank')));
    });

    test('access probe and asleep diagnostic', () async {
      bridge.granted = false;
      final (_, inbox) = await build();
      expect(inbox.accessGranted, isFalse);
      bridge.granted = true;
      bridge.connectedAt = now.subtract(const Duration(hours: 30));
      await inbox.refreshAccess();
      expect(inbox.accessGranted, isTrue);
      expect(inbox.listenerLooksAsleep, isTrue);
      await inbox.requestRebind();
      expect(bridge.rebinds, 1);
    });
  });
}
