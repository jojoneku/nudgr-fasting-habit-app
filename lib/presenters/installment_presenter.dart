import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_month_scope.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/safe_notifier.dart';
import 'package:intl/intl.dart';

// Sentinel for [InstallmentPresenter.buildInstallment]: "keep the category".
const Object _keepCategory = Object();

/// What the add/edit installment form shows under the interest-rate chips.
class InstallmentInterestPreview {
  final double totalInterest;
  final double totalPayable;

  /// "Interest: ₱1,440.00 (1%/mo) · Total payable: ₱13,440.00".
  final String label;

  const InstallmentInterestPreview({
    required this.totalInterest,
    required this.totalPayable,
    required this.label,
  });
}

class InstallmentPresenter extends ChangeNotifier with SafeNotifier {
  InstallmentPresenter(
    StorageService storage,
    LedgerPresenter ledger,
    StatsPresenter stats, {
    TreasuryMonthScope? monthScope,
  })  : _storage = storage,
        _ledger = ledger,
        _stats = stats,
        _monthScope = monthScope {
    if (monthScope != null) {
      _selectedMonth = monthScope.month;
      monthScope.addListener(_adoptScopeMonth);
    }
    _ledger.onSpawnInstallment = addInstallment;
    _ledger.onUpdateInstallment = updateInstallment;
    _ledger.onDeleteInstallment = _removePlan;
    _ledger.installmentResolver = findById;
    load();
  }

  final StorageService _storage;
  final LedgerPresenter _ledger;
  final StatsPresenter _stats;

  /// Shared "month being read" across the Treasury tabs; null when unshared.
  final TreasuryMonthScope? _monthScope;

  /// Another tab moved the shared month — follow it.
  void _adoptScopeMonth() {
    final month = _monthScope?.month;
    if (month == null || month == _selectedMonth) return;
    setMonth(month);
  }

  @override
  void dispose() {
    _monthScope?.removeListener(_adoptScopeMonth);
    if (_ledger.onSpawnInstallment == addInstallment) {
      _ledger.onSpawnInstallment = null;
    }
    if (_ledger.onUpdateInstallment == updateInstallment) {
      _ledger.onUpdateInstallment = null;
    }
    if (_ledger.onDeleteInstallment == _removePlan) {
      _ledger.onDeleteInstallment = null;
    }
    if (_ledger.installmentResolver == findById) {
      _ledger.installmentResolver = null;
    }
    super.dispose();
  }

  bool _isLoading = true;
  String _selectedMonth = toMonthKey(DateTime.now());
  List<Installment> _installments = [];

  /// Persisted one-time-XP-award guards (see [StorageService.keyAwardedXpKeys]).
  /// Without this, the completion (+50) and all-due-paid (+20) XP were
  /// re-awardable via markUnpaid/markPaid cycles.
  final Set<String> _awardedXpKeys = {};
  bool _awardedXpLoaded = false;

  // ─── Public state ─────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String get selectedMonth => _selectedMonth;
  List<FinancialAccount> get accounts => _ledger.accounts;
  List<FinanceCategory> get categories => _ledger.categories;

  /// Credit accounts (credit cards, credit lines, BNPL) eligible to hold
  /// installments. Non-liability accounts (savings, bank, cash) cannot hold
  /// borrowed installment debt.
  List<FinancialAccount> get creditAccounts =>
      _ledger.accounts.where((a) => a.isActive && a.isLiability).toList();

  void setMonth(String month) {
    _selectedMonth = month;
    _monthScope?.setMonth(month); // keep Ledger/Bills/Budget in step
    safeNotify();
  }

  // ─── Installment views ────────────────────────────────────────────────────────

  List<Installment> get installments =>
      _installments.where((i) => i.isActive).toList();

  List<Installment> get allInstallments => List.unmodifiable(_installments);

  List<Installment> get dueThisMonth => _installments
      .where((i) => i.isActive && i.isDueIn(_selectedMonth))
      .toList();

  /// Looks up an installment by id, or null when not found.
  Installment? findById(String id) =>
      _installments.where((i) => i.id == id).firstOrNull;

  /// Whether [selectedMonth]'s charge for [installmentId] is on the ledger.
  ///
  /// Counted, not keyed on a record's month: the plan has billed this month
  /// once its charges cover every schedule month up to it. A payment logged
  /// early (dated the month before) used to read as unpaid in its own month and
  /// get booked a second time.
  bool isPaidForMonth(String installmentId) {
    final inst = findById(installmentId);
    if (inst == null) return false;
    final due = inst.chargesDueBy(_selectedMonth);
    return due > 0 && inst.paidCount(_ledger.allTransactions) >= due;
  }

  /// True when [inst]'s card has a billing cycle, so each month is billed onto
  /// the card automatically when its statement closes and paid by paying the
  /// statement — there is nothing to mark paid on the row itself.
  bool billsOnStatement(Installment inst) =>
      accounts
          .where((a) => a.id == inst.accountId)
          .firstOrNull
          ?.hasBillingCycle ??
      false;

  /// Whether the row offers "Mark paid": only a plan on a card without a
  /// billing cycle (a BNPL with no statement), only once the plan has reached
  /// [selectedMonth], and only while that month is still open.
  bool canMarkPaid(Installment inst) =>
      !billsOnStatement(inst) &&
      inst.chargesDueBy(_selectedMonth) > 0 &&
      !isPaidForMonth(inst.id);

  /// Whether the row offers undoing this month's payment — the manual
  /// counterpart of [canMarkPaid]. A charge billed by a statement is not
  /// undone here; the next statement run would only bill it again.
  bool canMarkUnpaid(Installment inst) =>
      !billsOnStatement(inst) && isPaidForMonth(inst.id);

  /// The web row checkbox's tooltip: what ticking it does, or — on a card with
  /// statements — why there is nothing to tick.
  String checkboxTooltip(Installment inst) {
    if (billsOnStatement(inst)) {
      return isPaidForMonth(inst.id)
          ? 'Billed on the card statement'
          : 'Billed when the card statement closes';
    }
    return isPaidForMonth(inst.id) ? 'Mark unpaid this month' : 'Mark paid';
  }

  /// The row's status line: where this month's charge stands and which
  /// payment it is.
  String statusLabel(Installment inst) {
    final count = paidCount(inst.id);
    final total = inst.totalMonths;
    if (billsOnStatement(inst)) {
      return isPaidForMonth(inst.id)
          ? 'billed · $count/$total'
          : 'on statement · ${count + 1}/$total';
    }
    return isPaidForMonth(inst.id)
        ? 'paid · $count/$total'
        : 'payment ${count + 1}/$total';
  }

  int paidCount(String installmentId) =>
      _findById(installmentId).paidCount(_ledger.allTransactions);

  int remainingMonths(String installmentId) =>
      _findById(installmentId).remainingMonths(_ledger.allTransactions);

  double remainingAmount(String installmentId) =>
      _findById(installmentId).remainingAmount(_ledger.allTransactions);

  /// Fraction of payments made (0–1) for [installmentId], for progress bars.
  /// Kept here so views never compute it in `build`.
  double paymentProgress(String installmentId) {
    final inst = _findById(installmentId);
    if (inst.totalMonths <= 0) return 0.0;
    return (paidCount(installmentId) / inst.totalMonths).clamp(0.0, 1.0);
  }

  double get totalDueThisMonth =>
      dueThisMonth.fold(0.0, (sum, i) => sum + i.monthlyAmount);

  double get totalPaidThisMonth => dueThisMonth
      .where((i) => isPaidForMonth(i.id))
      .fold(0.0, (sum, i) => sum + i.monthlyAmount);

  // ─── Web helpers (Plan 050-C) ─────────────────────────────────────────────────

  /// Monthly installment cash load for the selected month — the web KPI strip's
  /// "Installment load". Alias of [totalDueThisMonth] for intent at the call site.
  double get monthlyInstallmentLoad => totalDueThisMonth;

  /// Human-readable account name for [accountId], or null when unknown. Keeps
  /// account lookups out of `build`.
  String? accountName(String? accountId) {
    if (accountId == null) return null;
    final match = accounts.where((a) => a.id == accountId).firstOrNull;
    return match?.name;
  }

  /// Formatted due date label (e.g. "Due Oct 5") when [inst] is linked
  /// to an account with a payment due date or cycle. Null when undated.
  String? dueLabel(Installment inst) {
    final due = dueDate(inst);
    if (due == null) return null;
    return 'Due ${DateFormat('MMM d').format(due)}';
  }

  /// Formatted interest rate badge label (e.g. "1%/mo int").
  /// Returns null when interestRate is 0 or not set.
  String? interestLabel(Installment inst) {
    if (!inst.hasInterest) return null;
    return '${rateText(inst.interestRate)}%/mo int';
  }

  /// "Bought Oct 19" for [inst], or null when no purchase date was recorded.
  String? purchasedLabel(Installment inst) {
    final date = inst.purchaseDate;
    if (date == null) return null;
    return 'Bought ${DateFormat('MMM d').format(date)}';
  }

  /// "Deferred 2 mos" for [inst], or null when the first payment wasn't
  /// deferred.
  String? deferralLabel(Installment inst) {
    final n = inst.deferralMonths;
    if (n <= 0) return null;
    return 'Deferred $n ${n == 1 ? 'mo' : 'mos'}';
  }

  /// The detail line under an installment row — account, purchase date,
  /// deferral, interest and due date, whichever apply — joined with " · ".
  /// Null when nothing applies. With [withRemaining] the amount still to be
  /// billed leads the line (the web row's layout).
  String? detailLine(Installment inst, {bool withRemaining = false}) {
    final parts = [
      if (withRemaining) '${formatPeso(remainingAmount(inst.id))} left',
      accountName(inst.accountId),
      purchasedLabel(inst),
      deferralLabel(inst),
      interestLabel(inst),
      dueLabel(inst),
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// The concrete due date of [inst] in the current [selectedMonth], or null
  /// if the linked account has no configured cycle or payment due day.
  ///
  /// [Installment.startMonth] (see [calculateInstallmentStartMonth]) counts
  /// months by when a payment is DUE, so on a billing-cycle account this is
  /// the due date of the statement that falls due in [selectedMonth] — not
  /// the one that closes in it, which under a "days after statement" rule is
  /// due the month after. Should no statement fall due in the month (a long
  /// days-after rule stepping over February) the date is unknown: null.
  DateTime? dueDate(Installment inst) {
    final account = accounts.where((a) => a.id == inst.accountId).firstOrNull;
    if (account == null) return null;
    final parts = _selectedMonth.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null) return null;

    if (account.hasBillingCycle) {
      // Due at most kMaxDueDaysAfterStatement days after close, so the close
      // is in this month or one of the two before it. Should two cycles fall
      // due in one month, the later statement wins (as in cycleForStatement).
      CreditCycle? match;
      for (var back = 2; back >= 0; back--) {
        final anchor = DateTime(y, m - back);
        final cycle = account.cycleClosingIn(anchor.year, anchor.month);
        if (cycle != null && cycle.dueMonthKey == _selectedMonth) {
          match = cycle;
        }
      }
      return match?.due;
    }
    if (account.paymentDueDay != null) {
      final lastDay = DateTime(y, m + 1, 0).day;
      return DateTime(y, m, account.paymentDueDay!.clamp(1, lastDay));
    }
    return null;
  }

  // ─── Add / edit form ──────────────────────────────────────────────────────────
  //
  // The mobile sheet and the web dialog both drive these, so the two forms
  // cannot drift on what they compute or what they save.

  /// Interest-rate chips offered by the add/edit forms (monthly add-on %).
  static const ratePresets = [0.0, 0.5, 1.0, 1.5, 2.0];

  /// True when [rate] is one of [ratePresets] (so no custom value is shown).
  static bool isPresetRate(double rate) => ratePresets.contains(rate);

  /// [rate] the way a person writes it: "1", "1.5", "1.25".
  static String rateText(double rate) {
    if (rate == rate.roundToDouble()) return rate.round().toString();
    return rate
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Chip label for a preset [rate]: "0% (Promo)", "1%", "1.5%".
  static String ratePresetLabel(double rate) =>
      rate == 0 ? '0% (Promo)' : '${rateText(rate)}%';

  /// First payment month for a purchase on [purchaseDate] charged to
  /// [accountId], deferred by [deferralMonths].
  String suggestedStartMonth({
    required String? accountId,
    required DateTime purchaseDate,
    int deferralMonths = 0,
  }) =>
      calculateInstallmentStartMonth(
        _accountById(accountId),
        purchaseDate,
        deferralMonths: deferralMonths,
      );

  /// The form's "which statement, due when" note, or null when the account
  /// has no billing cycle and nothing is deferred.
  String? cycleHint({
    required String? accountId,
    required DateTime purchaseDate,
    int deferralMonths = 0,
  }) =>
      installmentCycleExplanation(
        _accountById(accountId),
        purchaseDate,
        deferralMonths: deferralMonths,
      );

  /// Interest and total payable for the form's current input, or null when
  /// there is nothing to show (0%, or no principal yet).
  ///
  /// Totals follow the monthly payment actually being saved — [monthlyAmount]
  /// when the form has one (auto-filled or typed over), else the computed
  /// add-on payment — so "Total payable" always equals monthly × months.
  InstallmentInterestPreview? interestPreview({
    required double? principal,
    required int months,
    required double rate,
    double? monthlyAmount,
  }) {
    if (rate <= 0 || principal == null || principal <= 0 || months <= 0) {
      return null;
    }
    final monthly = (monthlyAmount != null && monthlyAmount > 0)
        ? monthlyAmount
        : Installment.computeMonthlyAmount(
            principal: principal, months: months, monthlyRate: rate);
    final totalPayable = monthly * months;
    final totalInterest = max(0.0, totalPayable - principal);
    return InstallmentInterestPreview(
      totalInterest: totalInterest,
      totalPayable: totalPayable,
      label: 'Interest: ${formatPeso(totalInterest)} (${rateText(rate)}%/mo)'
          ' · Total payable: ${formatPeso(totalPayable)}',
    );
  }

  /// Builds the installment the add/edit form describes. Editing keeps
  /// [existing]'s id and active flag. Leaving [categoryId] out keeps
  /// [existing]'s category (the web dialog has no category picker, and saving
  /// there must not wipe the one set on mobile); passing null clears it.
  Installment buildInstallment({
    Installment? existing,
    required String name,
    required String accountId,
    required double totalAmount,
    required double monthlyAmount,
    required int totalMonths,
    required String startMonth,
    required DateTime purchaseDate,
    int deferralMonths = 0,
    double interestRate = 0.0,
    String? note,
    Object? categoryId = _keepCategory,
  }) {
    final trimmedNote = note?.trim() ?? '';
    return Installment(
      id: existing?.id ?? _generateId(),
      name: name.trim(),
      accountId: accountId,
      totalAmount: totalAmount,
      monthlyAmount: monthlyAmount,
      totalMonths: totalMonths,
      startMonth: startMonth,
      purchaseDate: purchaseDate,
      deferralMonths: deferralMonths,
      interestRate: interestRate,
      note: trimmedNote.isEmpty ? null : trimmedNote,
      categoryId: identical(categoryId, _keepCategory)
          ? existing?.categoryId
          : categoryId as String?,
      isActive: existing?.isActive ?? true,
    );
  }

  /// Saves what the add/edit form built: updates it when [isEdit], else adds.
  Future<void> saveInstallment(Installment installment,
          {required bool isEdit}) =>
      isEdit ? updateInstallment(installment) : addInstallment(installment);

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    _installments = await _storage.loadInstallments();
    _awardedXpKeys
      ..clear()
      ..addAll(await _storage.loadAwardedXpKeys());
    _awardedXpLoaded = true;
    _isLoading = false;
    safeNotify();
    await _ledger.refreshInstallmentHolds();
  }

  /// Grants [xp] for [key] at most once (persisted), so unpay/re-pay cycles
  /// can't farm the completion / all-due-paid awards.
  Future<void> _awardOnce(String key, int xp) async {
    if (!_awardedXpLoaded) return;
    if (_awardedXpKeys.contains(key)) return;
    _awardedXpKeys.add(key);
    await _storage.saveAwardedXpKeys(_awardedXpKeys);
    await _stats.addXp(xp);
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────────

  Future<void> addInstallment(Installment i) async {
    _installments = [..._installments, i];
    safeNotify();
    await _storage.saveInstallments(_installments);
    await _ledger.refreshInstallmentHolds();
  }

  Future<void> updateInstallment(Installment i) async {
    _installments = [
      for (final inst in _installments) inst.id == i.id ? i : inst
    ];
    safeNotify();
    await _storage.saveInstallments(_installments);
    await _ledger.refreshInstallmentHolds();
  }

  /// Deletes the plan and every ledger record linked to it (its purchase and
  /// its payments). Single pass: one plan save, then one ledger mutation +
  /// persist — the ledger does not call back here.
  Future<void> deleteInstallment(String id) async {
    _installments = _installments.where((i) => i.id != id).toList();
    safeNotify();
    await _storage.saveInstallments(_installments);
    await _ledger.removeInstallmentRecords(id);
  }

  /// Ledger hook ([LedgerPresenter.onDeleteInstallment]): the ledger already
  /// removed the plan's records, so only the plan itself goes.
  Future<void> _removePlan(String id) async {
    if (!_installments.any((i) => i.id == id)) {
      // Not loaded into memory yet — remove it from storage directly rather
      // than saving a partial in-memory list over it.
      final stored = await _storage.loadInstallments();
      if (stored.any((i) => i.id == id)) {
        await _storage
            .saveInstallments(stored.where((i) => i.id != id).toList());
      }
      return;
    }
    _installments = _installments.where((i) => i.id != id).toList();
    safeNotify();
    await _storage.saveInstallments(_installments);
  }

  // ─── Mark paid / unpaid ───────────────────────────────────────────────────────

  /// Records this month of a plan on a card with no billing cycle — the same
  /// shape a statement close posts for a cycle card: the month is charged onto
  /// the card in the plan's category (raising its balance, releasing the hold),
  /// and when [fundingAccountId] names another account, a transfer from it pays
  /// that charge off. A no-op for a cycle card ([billsOnStatement]): its months
  /// are billed when the statement closes and settled by paying the statement.
  Future<void> markPaid(
    String installmentId, {
    double? overrideAmount,
    DateTime? date,
    String? fundingAccountId,
  }) async {
    final inst = _findById(installmentId);
    if (!canMarkPaid(inst)) return;
    final categoryId = inst.categoryId ?? kInstallmentCategoryId;
    if (inst.categoryId == null) {
      await _ensureInstallmentCategory();
    }

    final count = paidCount(installmentId) + 1;
    final when = date ?? DateTime.now();
    final txn = inst.chargeRecord(
      recordId: _generateId(),
      number: count,
      date: when,
      month: _selectedMonth,
      categoryId: categoryId,
      amount: overrideAmount,
    );
    await _ledger.addTransaction(txn);
    if (fundingAccountId != null && fundingAccountId != inst.accountId) {
      await _ledger.addTransfer(
        fromAccountId: fundingAccountId,
        toAccountId: inst.accountId,
        amount: txn.amount,
        description: _paymentDescription(inst),
        date: when,
      );
    }

    if (count >= inst.totalMonths) {
      await _awardOnce('installment.complete/$installmentId', 50);
    }

    final allDuePaid = dueThisMonth.every(
      (i) => i.id == installmentId || isPaidForMonth(i.id),
    );
    if (allDuePaid && dueThisMonth.isNotEmpty) {
      await _awardOnce('installment.allDuePaid/$_selectedMonth', 20);
    }

    safeNotify();
    await _ledger.refreshInstallmentHolds();
  }

  /// Reverses this month's payment by deleting the charge that records it — an
  /// installment has no separate paid flag, the charge IS the record — along
  /// with the funding transfer [markPaid] booked beside it, if any. Prefers the
  /// charge filed under this month, else the latest one. A no-op when the
  /// month is already unpaid (so a double-tap, or an undo racing a reload,
  /// can't throw) and for a cycle card, whose charges the statement owns.
  Future<void> markUnpaid(String installmentId) async {
    final inst = findById(installmentId);
    if (inst == null || !canMarkUnpaid(inst)) return;
    final charges = _ledger.allTransactions
        .where((t) => t.installmentId == installmentId && !t.isInstallment)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final txn = charges.where((t) => t.month == _selectedMonth).lastOrNull ??
        charges.lastOrNull;
    if (txn == null) return;
    await _ledger.deleteTransaction(txn.id);
    // The transfer is matched tightly — into this card, same day, same amount,
    // same description — so an unrelated payment is never unwound.
    final transfer = _ledger.allTransactions
        .where((t) =>
            t.transferGroupId != null &&
            t.type == TransactionType.inflow &&
            t.accountId == inst.accountId &&
            (t.amount - txn.amount).abs() < 0.005 &&
            _sameDay(t.date, txn.date) &&
            t.description == _paymentDescription(inst))
        .firstOrNull;
    if (transfer != null) {
      await _ledger.deleteTransactionOrGroup(transfer.id);
    }
    safeNotify();
    await _ledger.refreshInstallmentHolds();
  }

  // ─── Batch actions ────────────────────────────────────────────────────────────
  //
  // Driven by the Bills tab's selection mode. Each is tolerant: ids that are
  // unknown, inactive, or already in the target state are skipped rather than
  // throwing, so one bad row can't abandon the rest of the selection.

  /// Records this month's payment for every installment in [ids] that hasn't
  /// been paid yet, each from its own account for its own monthly amount.
  /// Returns how many were paid.
  Future<int> markManyPaid(Iterable<String> ids, {DateTime? date}) async {
    var applied = 0;
    for (final id in ids.toSet()) {
      final inst = _installments.where((i) => i.id == id).firstOrNull;
      if (inst == null || !canMarkPaid(inst)) continue;
      await markPaid(id, date: date);
      applied++;
    }
    return applied;
  }

  /// Reverses this month's payment for every installment in [ids]. Returns how
  /// many were reversed.
  Future<int> markManyUnpaid(Iterable<String> ids) async {
    var applied = 0;
    for (final id in ids.toSet()) {
      final inst = findById(id);
      if (inst == null || !canMarkUnpaid(inst)) continue;
      await markUnpaid(id);
      applied++;
    }
    return applied;
  }

  /// Deletes every installment in [ids] along with its payment transactions.
  /// Returns how many existed.
  Future<int> deleteInstallments(Iterable<String> ids) async {
    var applied = 0;
    for (final id in ids.toSet()) {
      if (!_installments.any((i) => i.id == id)) continue;
      await deleteInstallment(id);
      applied++;
    }
    return applied;
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  Installment _findById(String id) =>
      _installments.firstWhere((i) => i.id == id);

  FinancialAccount? _accountById(String? id) =>
      id == null ? null : accounts.where((a) => a.id == id).firstOrNull;

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  String _paymentDescription(Installment inst) => '${inst.name} payment';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _ensureInstallmentCategory() async {
    final exists =
        _ledger.categories.any((c) => c.id == kInstallmentCategoryId);
    if (!exists) {
      await _ledger.addCategory(installmentFallbackCategory());
    }
  }
}
