import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/finance/capture_settings.dart';
import '../models/finance/captured_transaction.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/raw_capture.dart';
import '../models/finance/transaction_record.dart';
import '../services/capture_bridge_service.dart';
import '../services/finance_personal_dictionary.dart';
import '../services/storage_service.dart';
import '../utils/capture_parser.dart';
import '../utils/capture_templates.dart';
import '../utils/finance_format.dart';
import '../utils/safe_notifier.dart';
import 'ledger_presenter.dart';

/// Owns the Capture Inbox: notifications the native listener queued, parsed
/// into draft transactions, waiting for the user to approve or decline.
///
/// The ledger stays the owner of transactions. Approving a row builds a record
/// and hands it to [LedgerPresenter.addTransaction] (or `addTransfer`), which
/// is also where the first-log-of-the-day XP already lives, so approval awards
/// nothing of its own. Accounts and categories are read live off the ledger —
/// this presenter mirrors by listening, it keeps no copy (CLAUDE.md rule 8).
///
/// Nothing is ever posted without a tap. See
/// `.claude/plans/070-capture-inbox.md`.
class CaptureInboxPresenter extends ChangeNotifier with SafeNotifier {
  CaptureInboxPresenter(
    StorageService storage,
    LedgerPresenter ledger,
    CaptureBridgeService bridge, {
    FinancePersonalDictionary? dict,
    DateTime Function()? clock,
  })  : _storage = storage,
        _ledger = ledger,
        _bridge = bridge,
        _dict = dict,
        _clock = clock ?? DateTime.now {
    _ledger.addListener(_onLedgerChanged);
  }

  final StorageService _storage;
  final LedgerPresenter _ledger;
  final CaptureBridgeService _bridge;
  final FinancePersonalDictionary? _dict;
  final DateTime Function() _clock;

  static const Duration declinedRetention = Duration(days: 30);
  static const Duration approvedRetention = Duration(days: 7);

  List<CapturedTransaction> _items = const [];
  CaptureSettings _settings = const CaptureSettings();
  bool _accessGranted = false;
  bool _isDraining = false;
  bool _loaded = false;
  DateTime? _lastConnectedAt;

  @override
  void dispose() {
    _ledger.removeListener(_onLedgerChanged);
    super.dispose();
  }

  /// Account and category lists changed under the chips; repaint. Pending
  /// rows with no account also get another look: a row filed before the
  /// ledger had loaded (load() runs alongside it) or before the matching
  /// account existed now lands on the account named like its source app.
  void _onLedgerChanged() {
    unawaited(_fillSourceAccounts());
    safeNotify();
  }

  /// Fills the account on pending rows that have none, from the per-source
  /// mapping or the account whose name matches the source app. Persists only
  /// when a row changed.
  Future<void> _fillSourceAccounts() async {
    if (!_loaded || !_applySourceAccounts()) return;
    safeNotify();
    await _persistItems();
  }

  /// Same, without persisting. Returns true when any row changed.
  bool _applySourceAccounts() {
    var changed = false;
    _items = [
      for (final i in _items)
        if (i.isPending && i.draft.accountId == null)
          _withSourceAccount(i, onChange: () => changed = true)
        else
          i,
    ];
    return changed;
  }

  CapturedTransaction _withSourceAccount(CapturedTransaction item,
      {required void Function() onChange}) {
    final id = resolveSourceAccount(
      packageName: item.sourceApp,
      appLabel: item.sourceLabel,
      settings: _settings,
      accounts: _ledger.accounts,
    );
    if (id == null || id == item.draft.transferToAccountId) return item;
    onChange();
    return item.copyWith(
      draft: item.draft.copyWith(accountId: id),
      updatedAt: _clock(),
    );
  }

  /// Drops pending rows that [parseCapture] no longer files — the reject
  /// filter is text-only, so a row's own raw title and text decide. Returns
  /// true when any went.
  bool _dropRejectedPending() {
    final before = _items.length;
    _items = _items.where((i) {
      if (!i.isPending) return true;
      final raw = RawCapture(
        packageName: i.sourceApp,
        appLabel: i.sourceLabel,
        postedAt: i.capturedAt,
        title: i.rawTitle,
        text: i.rawText,
        fingerprint: i.fingerprint,
      );
      return parseCapture(
            raw,
            settings: _settings,
            accounts: _ledger.accounts,
            categories: _ledger.categories,
            dict: _dict,
            now: _clock(),
          ) !=
          null;
    }).toList();
    return _items.length != before;
  }

  // ── State ──────────────────────────────────────────────────────────────────

  bool get isSupported => _bridge.isSupported;
  bool get isLoaded => _loaded;
  CaptureSettings get settings => _settings;
  bool get isEnabled => _settings.enabled;
  bool get accessGranted => _accessGranted;
  bool get isDraining => _isDraining;
  DateTime? get lastCaptureAt => _settings.lastCaptureAt;
  DateTime? get lastConnectedAt => _lastConnectedAt;

  /// Capture is on but the listener has not connected for a day: the OEM
  /// battery manager probably killed it. Settings offers *Reconnect*.
  bool get listenerLooksAsleep {
    if (!_settings.enabled || !_accessGranted) return false;
    final at = _lastConnectedAt;
    if (at == null) return false;
    return _clock().difference(at) > const Duration(hours: 24);
  }

  /// Whether anything about capture should show in the Ledger at all.
  bool get hasPresence => _settings.enabled || _items.any((i) => i.isPending);

  List<CapturedTransaction> get pending =>
      _items.where((i) => i.isPending).toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

  List<CapturedTransaction> get recentlyResolved {
    final cutoff = _clock().subtract(approvedRetention);
    return _items
        .where((i) => !i.isPending && (i.resolvedAt?.isAfter(cutoff) ?? false))
        .toList()
      ..sort((a, b) =>
          (b.resolvedAt ?? b.updatedAt).compareTo(a.resolvedAt ?? a.updatedAt));
  }

  int get pendingCount => _items.where((i) => i.isPending).length;
  int get readyCount => _items.where((i) => i.isPending && i.isReady).length;

  CapturedTransaction? byId(String id) =>
      _items.where((i) => i.id == id).firstOrNull;

  /// Live lists for the row chips.
  List<FinancialAccount> get accounts =>
      _ledger.accounts.where((a) => a.isActive).toList();
  List<FinanceCategory> get categories => _ledger.categories;

  FinancialAccount? accountById(String? id) =>
      id == null ? null : _ledger.accounts.where((a) => a.id == id).firstOrNull;
  FinanceCategory? categoryById(String? id) => id == null
      ? null
      : _ledger.categories.where((c) => c.id == id).firstOrNull;

  /// The ledger already holds a record with the same amount, day and account
  /// that this row did not create — the user probably logged it by hand.
  bool isPossibleDuplicate(CapturedTransaction c) {
    final d = c.draft;
    if (d.amount == null || d.accountId == null || d.date == null) return false;
    final day = DateTime(d.date!.year, d.date!.month, d.date!.day);
    return _ledger.allTransactions.any((t) =>
        t.id != c.transactionId &&
        t.accountId == d.accountId &&
        (t.amount - d.amount!).abs() < 0.005 &&
        DateTime(t.date.year, t.date.month, t.date.day) == day);
  }

  /// One payment, two notifications: Google Wallet and the card's own app
  /// (or a bank push and its email) both report the same amount within
  /// minutes. The earlier pending row is the one to keep; this returns it for
  /// a later row that repeats it, or null.
  CapturedTransaction? twinOf(CapturedTransaction c) {
    final twins = _twinsOf(c).where((t) => t.capturedAt.isBefore(c.capturedAt));
    return twins.isEmpty ? null : twins.first;
  }

  static const Duration twinWindow = Duration(minutes: 15);

  Iterable<CapturedTransaction> _twinsOf(CapturedTransaction c) {
    return pending.where((t) {
      if (t.id == c.id || t.sourceApp == c.sourceApp) return false;
      if (t.capturedAt.difference(c.capturedAt).abs() > twinWindow) {
        return false;
      }
      return _sameAmount(t, c) || _echoOf(t, c) || _echoOf(c, t);
    });
  }

  /// Same figure, and a direction that does not contradict: equal, unknown on
  /// one side, or a transfer on one side (a bank's inflow email and the
  /// sender app's transfer push are the same movement).
  static bool _sameAmount(CapturedTransaction a, CapturedTransaction b) {
    final x = a.draft.amount, y = b.draft.amount;
    if (x == null || y == null || (x - y).abs() >= 0.005) return false;
    final tx = a.draft.type, ty = b.draft.type;
    return tx == null ||
        ty == null ||
        tx == ty ||
        tx == TransactionType.transfer ||
        ty == TransactionType.transfer;
  }

  /// A bank email cut off before its figure ("Incoming Interbank Funds
  /// Transfer … Needs amount") that lands in the same account a transfer push
  /// already moves money into. The push carries the amount; the email does
  /// not, so the amount rule cannot see them.
  static bool _echoOf(CapturedTransaction echo, CapturedTransaction push) {
    if (echo.draft.amount != null) return false;
    final pd = push.draft, ed = echo.draft;
    if (pd.type != TransactionType.transfer || pd.transferToAccountId == null) {
      return false;
    }
    return (ed.type == TransactionType.inflow &&
            ed.accountId == pd.transferToAccountId) ||
        (ed.type == TransactionType.transfer &&
            ed.transferToAccountId == pd.transferToAccountId);
  }

  /// Source labels of the rows the last [approve] declined as twins.
  List<String> get lastAutoDeclinedLabels =>
      List.unmodifiable(_lastAutoDeclined);
  List<String> _lastAutoDeclined = const [];

  /// Sources offered in Settings: presets first, then anything the user
  /// added, each with its current enabled state.
  List<({String package, String label, bool enabled})> get sourceRows {
    final seen = <String>{};
    final rows = <({String package, String label, bool enabled})>[];
    for (final p in kCapturePresets) {
      seen.add(p.package);
      rows.add((
        package: p.package,
        label: _settings.sourceLabels[p.package] ?? p.label,
        enabled: _settings.sources.contains(p.package),
      ));
    }
    for (final pkg in _settings.sources) {
      if (seen.add(pkg)) {
        rows.add((package: pkg, label: _settings.labelFor(pkg), enabled: true));
      }
    }
    return rows;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      _settings = await _storage.loadCaptureSettings();
      _items = await _storage.loadCaptureInbox();
    } catch (e) {
      debugPrint('CaptureInboxPresenter: load failed: $e');
    }
    _loaded = true;
    // Rows the filter would now reject (a promo cue learned since they were
    // filed) go, so a parser fix also cleans the inbox the user is looking at.
    var changed = _purgeExpired();
    if (_dropRejectedPending()) changed = true;
    if (_applySourceAccounts()) changed = true;
    if (changed) await _persistItems();
    safeNotify();
    if (!_bridge.isSupported) return;
    // Re-assert the allowlist: a reinstall or a cleared native store must not
    // leave the listener keeping nothing (or, worse, keeping everything).
    await _pushAllowlist();
    await refreshAccess();
    if (_settings.enabled && _accessGranted) await drain();
  }

  /// Probes system access and the listener's last connection. Called on
  /// resume so returning from the system settings page updates the UI.
  Future<void> refreshAccess() async {
    if (!_bridge.isSupported) return;
    final granted = await _bridge.isAccessGranted();
    final connected = await _bridge.lastConnectedAt();
    if (granted != _accessGranted || connected != _lastConnectedAt) {
      _accessGranted = granted;
      _lastConnectedAt = connected;
      safeNotify();
    }
  }

  /// Pulls the native queue, parses each capture and files it as pending.
  /// Idempotent: the native queue is cleared only after the rows persist; on
  /// a failed persist they are pushed back. Returns how many rows were added.
  Future<int> drain() async {
    if (!_settings.enabled || !_bridge.isSupported || _isDraining) return 0;
    _isDraining = true;
    safeNotify();
    try {
      final raw = await _bridge.drainRaw();
      if (raw.isEmpty) return 0;
      final added = _fileCaptures(raw);
      if (added.isEmpty) return 0;
      final before = _items;
      _items = [..._items, ...added];
      final newest =
          added.map((c) => c.capturedAt).reduce((a, b) => a.isAfter(b) ? a : b);
      _settings = _settings.copyWith(
        lastCaptureAt: (_settings.lastCaptureAt == null ||
                newest.isAfter(_settings.lastCaptureAt!))
            ? newest
            : _settings.lastCaptureAt,
        lastDrainAt: _clock(),
      );
      safeNotify();
      try {
        await _persistItems();
        await _persistSettings();
      } catch (e) {
        debugPrint('CaptureInboxPresenter: persist after drain failed: $e');
        _items = before;
        await _bridge.requeue(raw);
        safeNotify();
        return 0;
      }
      return added.length;
    } finally {
      _isDraining = false;
      safeNotify();
    }
  }

  /// Files [raw] captures the same way [drain] does, without touching the
  /// native queue. The share-sheet path (phase 3) and tests use it.
  Future<int> fileRaw(List<RawCapture> raw) async {
    final added = _fileCaptures(raw);
    if (added.isEmpty) return 0;
    _items = [..._items, ...added];
    safeNotify();
    await _persistItems();
    return added.length;
  }

  List<CapturedTransaction> _fileCaptures(List<RawCapture> raw) {
    final known = {
      for (final i in _items) i.fingerprint,
      for (final i in _items) i.id,
    };
    final added = <CapturedTransaction>[];
    for (final r in raw) {
      // Defense in depth: the listener already filters by allowlist.
      if (!_settings.sources.contains(r.packageName)) continue;
      if (r.fingerprint.isNotEmpty && known.contains(r.fingerprint)) continue;
      final parsed = parseCapture(
        r,
        settings: _settings,
        accounts: _ledger.accounts,
        categories: _ledger.categories,
        dict: _dict,
        now: _clock(),
      );
      // An OTP, a promo or a failed transaction is not a row at all.
      if (parsed == null) continue;
      if (known.contains(parsed.id) || known.contains(parsed.fingerprint)) {
        continue;
      }
      known.add(parsed.fingerprint);
      known.add(parsed.id);
      added.add(parsed);
    }
    return added;
  }

  // ── Review ─────────────────────────────────────────────────────────────────

  /// Chip edits and the Add Transaction sheet both land here.
  Future<void> setDraft(String id, ParsedTransaction draft) async {
    final item = byId(id);
    if (item == null || !item.isPending) return;
    _replace(item.copyWith(draft: draft, updatedAt: _clock()));
    safeNotify();
    await _persistItems();
  }

  /// Posts the row to the ledger. Throws [StateError] when it is not ready.
  Future<TransactionRecord?> approve(String id) async {
    final item = byId(id);
    if (item == null || !item.isPending) return null;
    if (!item.isReady) {
      throw StateError('Capture $id is missing ${item.missing}');
    }
    final d = item.draft;
    final date = d.date ?? item.capturedAt;
    final description = d.description.isNotEmpty
        ? d.description
        : '${item.sourceLabel} transaction';

    TransactionRecord? posted;
    if (d.type == TransactionType.transfer) {
      await _ledger.addTransfer(
        fromAccountId: d.accountId!,
        toAccountId: d.transferToAccountId!,
        amount: d.amount!,
        description: description,
        date: date,
        note: d.note,
      );
      posted = _ledger.allTransactions.lastWhere(
        (t) =>
            t.transferGroupId != null &&
            t.type == TransactionType.outflow &&
            t.accountId == d.accountId &&
            t.transferToAccountId == d.transferToAccountId &&
            (t.amount - d.amount!).abs() < 0.005,
        orElse: () => _ledger.allTransactions.last,
      );
    } else {
      posted = TransactionRecord(
        id: _generateId(),
        date: date,
        accountId: d.accountId!,
        categoryId: d.categoryId!,
        amount: d.amount!,
        type: d.type!,
        description: description,
        note: d.note,
        month: toMonthKey(date),
      );
      await _ledger.addTransaction(posted);
    }

    final at = _clock();
    _replace(item.copyWith(
      status: CaptureStatus.approved,
      resolvedAt: at,
      transactionId: posted.id,
      updatedAt: at,
    ));
    // The same payment reported by another app is declined with the same
    // stamp, so an Undo of this approve brings it back too.
    final twins = _twinsOf(item).toList();
    for (final t in twins) {
      _replace(t.copyWith(
          status: CaptureStatus.declined, resolvedAt: at, updatedAt: at));
    }
    _lastAutoDeclined = [for (final t in twins) t.sourceLabel];
    safeNotify();
    await _persistItems();
    return posted;
  }

  /// Posts every pending row that is ready. Returns how many posted.
  Future<int> approveAllReady() async {
    final ids = pending.where((c) => c.isReady).map((c) => c.id).toList();
    var n = 0;
    for (final id in ids) {
      try {
        if (await approve(id) != null) n++;
      } catch (e) {
        debugPrint('CaptureInboxPresenter: approve $id failed: $e');
      }
    }
    return n;
  }

  Future<void> decline(String id) async {
    final item = byId(id);
    if (item == null || !item.isPending) return;
    _replace(item.copyWith(
      status: CaptureStatus.declined,
      resolvedAt: _clock(),
      updatedAt: _clock(),
    ));
    safeNotify();
    await _persistItems();
  }

  Future<int> declineAll() async {
    final ids = pending.map((c) => c.id).toList();
    if (ids.isEmpty) return 0;
    final now = _clock();
    _items = [
      for (final i in _items)
        ids.contains(i.id)
            ? i.copyWith(
                status: CaptureStatus.declined, resolvedAt: now, updatedAt: now)
            : i,
    ];
    safeNotify();
    await _persistItems();
    return ids.length;
  }

  /// Reverses the last decision: an approved row's ledger record (both legs
  /// of a transfer) is deleted; either way the row is pending again.
  Future<void> undo(String id) async {
    final item = byId(id);
    if (item == null || item.isPending) return;
    if (item.status == CaptureStatus.approved) {
      final stamp = item.resolvedAt;
      for (final t in _items) {
        if (t.id != item.id &&
            t.status == CaptureStatus.declined &&
            t.resolvedAt == stamp) {
          _replace(t.copyWith(
            status: CaptureStatus.pending,
            clearResolvedAt: true,
            updatedAt: _clock(),
          ));
        }
      }
    }
    if (item.status == CaptureStatus.approved && item.transactionId != null) {
      final posted = _ledger.allTransactions
          .where((t) => t.id == item.transactionId)
          .firstOrNull;
      if (posted != null) {
        final group = posted.transferGroupId;
        final legs = group == null
            ? [posted]
            : _ledger.allTransactions
                .where((t) => t.transferGroupId == group)
                .toList();
        for (final leg in legs) {
          await _ledger.deleteTransaction(leg.id);
        }
      }
    }
    _replace(item.copyWith(
      status: CaptureStatus.pending,
      clearResolvedAt: true,
      clearTransactionId: true,
      updatedAt: _clock(),
    ));
    safeNotify();
    await _persistItems();
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  /// Turning capture on seeds the preset sources when the list is empty.
  /// Turning it off empties the native allowlist so nothing more is kept.
  Future<void> setEnabled(bool value) async {
    var next = _settings.copyWith(enabled: value);
    if (value && next.sources.isEmpty) {
      next = next.copyWith(
        sources: kCapturePresets.map((p) => p.package).toSet(),
        sourceLabels: {
          ...next.sourceLabels,
          for (final p in kCapturePresets) p.package: p.label,
        },
        senderFilters: {...kCaptureSenderFilterDefaults, ...next.senderFilters},
      );
    }
    await _applySettings(next);
    if (value) {
      await refreshAccess();
      if (_accessGranted) await drain();
    }
  }

  Future<void> setSourceEnabled(
      String package, String label, bool value) async {
    final sources = {..._settings.sources};
    if (value) {
      sources.add(package);
    } else {
      sources.remove(package);
    }
    // A source that needs a sender filter (Gmail) starts with the default
    // list, never wide open.
    final filters = {..._settings.senderFilters};
    final seed = kCaptureSenderFilterDefaults[package];
    if (value && seed != null && !filters.containsKey(package)) {
      filters[package] = seed;
    }
    await _applySettings(_settings.copyWith(
      sources: sources,
      sourceLabels: {..._settings.sourceLabels, package: label},
      senderFilters: filters,
    ));
  }

  Future<void> setSourceAccount(String package, String? accountId) async {
    final map = {..._settings.accountBySource};
    if (accountId == null) {
      map.remove(package);
    } else {
      map[package] = accountId;
    }
    await _applySettings(_settings.copyWith(accountBySource: map));
  }

  Future<void> setLast4Account(String last4, String? accountId) async {
    final map = {..._settings.accountByLast4};
    if (accountId == null) {
      map.remove(last4);
    } else {
      map[last4] = accountId;
    }
    await _applySettings(_settings.copyWith(accountByLast4: map));
  }

  Future<List<RecentApp>> recentApps() => _bridge.recentApps();
  Future<void> openAccessSettings() => _bridge.openAccessSettings();
  Future<void> requestRebind() => _bridge.requestRebind();

  Future<void> _applySettings(CaptureSettings next) async {
    _settings = next;
    safeNotify();
    await _persistSettings();
    if (_bridge.isSupported) await _pushAllowlist();
  }

  Future<void> _pushAllowlist() => _bridge.setAllowlist(
        _settings.enabled ? _settings.sources : const {},
        titleFilters: _settings.enabled ? _settings.senderFilters : const {},
      );

  // ── Internals ──────────────────────────────────────────────────────────────

  void _replace(CapturedTransaction item) {
    _items = [for (final i in _items) i.id == item.id ? item : i];
  }

  /// Drops resolved rows past their retention. Returns true when any went.
  bool _purgeExpired() {
    final now = _clock();
    final before = _items.length;
    _items = _items.where((i) {
      final at = i.resolvedAt;
      if (i.isPending || at == null) return true;
      final keep = i.status == CaptureStatus.declined
          ? declinedRetention
          : approvedRetention;
      return now.difference(at) <= keep;
    }).toList();
    return _items.length != before;
  }

  Future<void> _persistItems() => _storage.saveCaptureInbox(_items);
  Future<void> _persistSettings() => _storage.saveCaptureSettings(_settings);

  String _generateId() =>
      '${_clock().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
}
