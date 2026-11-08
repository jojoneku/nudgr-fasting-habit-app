import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/settle_copy.dart';
import 'package:intermittent_fasting/utils/settle_rules.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';

/// Keys for the Settle sheet's controls, for tests and callers that drive it.
abstract final class SettleSheetKeys {
  static const amount = ValueKey('settle-sheet-amount');
  static const account = ValueKey('settle-sheet-account');
  static const destination = ValueKey('settle-sheet-destination');
  static const date = ValueKey('settle-sheet-date');
  static const shortBalance = ValueKey('settle-sheet-short-balance');
  static const alreadyLogged = ValueKey('settle-sheet-already-logged');
  static const batchRows = ValueKey('settle-sheet-batch-rows');
  static const confirm = ValueKey('settle-sheet-confirm');
}

/// The one mobile sheet behind every "this is now paid / received / funded"
/// action (Plan 071 Phase 5): bills, receivables, set-asides, installments and
/// card payments; one row or a batch.
///
/// Single mode (one target) asks for the amount (editable — a partial payment,
/// an overpayment, a rounded final installment), the account, and the date.
/// Batch mode (several targets) lists the rows and asks once for what they
/// share: the account and the date; each row settles for its own amount.
///
/// [payers] are the eligible funding (or deposit) accounts, from the
/// presenter. The picker is skipped for [SettleKind.installment], which rides
/// on its own card. A short balance is named under the picker but does not
/// block; a card payment above what is owed is blocked.
///
/// [destinations] and [savedDestinationCount] drive the set-aside "Set aside
/// into" question. With no destinations at all there is nothing to choose, so
/// the money is spent (no transfer).
///
/// The sheet only collects input. [onConfirm] is the caller's own presenter
/// call: the sheet awaits it, closes and returns the [SettleResult] when it
/// succeeds, and stays open with an error toast when it throws. Returns null
/// when dismissed.
///
/// [emptyPayersMessage] replaces the default line shown in single mode when
/// there is no account to pick.
Future<SettleResult?> showSettleSheet(
  BuildContext context, {
  required SettleKind kind,
  required List<SettleTarget> targets,
  required List<FinancialAccount> payers,
  required Future<void> Function(SettleResult result) onConfirm,
  String? initialAccountId,
  List<FinancialAccount> destinations = const [],
  int savedDestinationCount = 0,
  String? emptyPayersMessage,
}) {
  assert(targets.isNotEmpty, 'Settle needs at least one target');
  return showModalBottomSheet<SettleResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SettleSheet(
      kind: kind,
      targets: targets,
      payers: payers,
      onConfirm: onConfirm,
      initialAccountId: initialAccountId,
      destinations: destinations,
      savedDestinationCount: savedDestinationCount,
      emptyPayersMessage: emptyPayersMessage,
    ),
  );
}

/// Pays down a credit (liability) [card] through [showSettleSheet] with
/// [SettleKind.cardPayment]: cash leaves the picked account and the card's
/// owed balance drops via [BillsReceivablesPresenter.quickPayCard]. Shared by
/// every mobile "Pay card" button so it behaves the same wherever it is
/// launched from. Returns the result once the payment is saved, or null.
Future<SettleResult?> showCardPaymentSheet(
  BuildContext context, {
  required FinancialAccount card,
  required BillsReceivablesPresenter presenter,
}) {
  return showSettleSheet(
    context,
    kind: SettleKind.cardPayment,
    targets: [
      SettleTarget(id: card.id, name: card.name, amount: card.currentPayable),
    ],
    payers: presenter.cardPayerAccounts,
    emptyPayersMessage: 'No liquid accounts available.',
    onConfirm: (r) => presenter.quickPayCard(
      accountId: card.id,
      fromAccountId: r.accountId!,
      amount: r.amount,
      date: r.date,
    ),
  );
}

/// The body of [showSettleSheet]. Public so tests can find it; open it
/// through [showSettleSheet].
class SettleSheet extends StatefulWidget {
  final SettleKind kind;
  final List<SettleTarget> targets;
  final List<FinancialAccount> payers;
  final Future<void> Function(SettleResult result) onConfirm;
  final String? initialAccountId;
  final List<FinancialAccount> destinations;
  final int savedDestinationCount;
  final String? emptyPayersMessage;

  const SettleSheet({
    super.key,
    required this.kind,
    required this.targets,
    required this.payers,
    required this.onConfirm,
    this.initialAccountId,
    this.destinations = const [],
    this.savedDestinationCount = 0,
    this.emptyPayersMessage,
  });

  @override
  State<SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<SettleSheet> {
  late final TextEditingController _amountController;
  String? _amountError;
  String? _accountId;
  String? _destinationId;

  /// The destination question has been answered — an account, or an explicit
  /// "spend it". Kept apart from [_destinationId] because null is itself a
  /// valid answer.
  late bool _destinationChosen;
  bool _useSavedDestinations = true;
  DateTime _date = DateTime.now();
  bool _alreadyInLedger = false;
  bool _submitting = false;

  SettleKind get _kind => widget.kind;
  bool get _isBatch => widget.targets.length > 1;
  SettleTarget get _single => widget.targets.first;
  int get _count => widget.targets.length;

  SettleCopy get _copy =>
      SettleCopy(kind: _kind, targets: widget.targets, isBatch: _isBatch);

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: _single.amount.toStringAsFixed(2));
    // Only honour a preselection the picker can actually offer.
    final wanted =
        widget.initialAccountId ?? (_isBatch ? null : _single.accountId);
    _accountId = widget.payers.any((a) => a.id == wanted)
        ? wanted
        : widget.payers.firstOrNull?.id;
    // The destination on file must be on offer, and can never be the funding
    // account (money can't move into the account it left).
    final onFile = _isBatch ? null : _single.destinationId;
    _destinationId = onFile != null &&
            onFile != _accountId &&
            widget.destinations.any((a) => a.id == onFile)
        ? onFile
        : null;
    // A set-aside with nothing on file starts with the question open; a
    // destination is never guessed.
    _destinationChosen = _kind != SettleKind.setAside || _destinationId != null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // ── What this kind asks for ───────────────────────────────────────────────

  bool get _offersLedgerToggle => settleOffersLedgerToggle(_kind);
  bool get _recordsInLedger => !(_offersLedgerToggle && _alreadyInLedger);
  bool get _asksAccount =>
      settleAsksAccount(_kind, recordInLedger: _recordsInLedger);
  bool get _isSetAside => _kind == SettleKind.setAside;

  bool get _showsAmount => !_isBatch;
  bool get _showsAccountPicker => _asksAccount && widget.payers.isNotEmpty;
  bool get _showsNoPayers => _asksAccount && widget.payers.isEmpty;

  /// Batch set-asides: rows with no destination of their own, which the shared
  /// destination applies to.
  int get _unnamedDestinations => !_isBatch
      ? 1
      : _useSavedDestinations
          ? _count - widget.savedDestinationCount
          : _count;

  /// With no destination accounts at all there is nothing to choose: the money
  /// is spent. Same rule the set-aside sheet had before the merge.
  bool get _asksDestination =>
      _isSetAside &&
      _recordsInLedger &&
      _unnamedDestinations > 0 &&
      widget.destinations.isNotEmpty;

  bool get _showsSavedDestinationToggle =>
      _isSetAside && _isBatch && widget.savedDestinationCount > 0;

  List<FinancialAccount> get _destinationOptions => [
        for (final a in widget.destinations)
          if (a.id != _accountId) a,
      ];

  FinancialAccount? get _account =>
      widget.payers.where((a) => a.id == _accountId).firstOrNull;

  FinancialAccount? get _destination =>
      widget.destinations.where((a) => a.id == _destinationId).firstOrNull;

  /// The figure that will leave (or enter) the account.
  double get _movingAmount =>
      _isBatch ? _copy.total : (parseSettleAmount(_amountController.text) ?? 0);

  String? get _shortBalanceNote => !_showsAccountPicker
      ? null
      : settleShortBalanceNote(
          kind: _kind,
          amount: _movingAmount,
          from: _account,
        );

  bool get _canConfirm {
    if (_submitting) return false;
    // Single mode needs an account whenever it records the movement. A batch
    // with no eligible account goes through flagged settled without a ledger
    // entry instead.
    if (!_isBatch && _asksAccount && _accountId == null) return false;
    if (_asksDestination && !_destinationChosen) return false;
    return true;
  }

  // ── Copy ─────────────────────────────────────────────────────────────────

  String get _destinationLabel =>
      _isBatch && widget.savedDestinationCount > 0 && _useSavedDestinations
          ? 'Set the other $_unnamedDestinations aside into'
          : 'Set aside into';

  String get _destinationPlaceholder =>
      _destinationChosen ? 'Spend it (no transfer)' : 'Choose where it goes';

  String get _noPayersMessage => _isBatch
      ? 'No account can cover this whole selection. They will be flagged '
          'settled without a ledger entry.'
      : widget.emptyPayersMessage ?? 'Add an account before settling.';

  String get _savedDestinationTitle =>
      '${widget.savedDestinationCount} of $_count have their own destination';

  String get _savedDestinationSubtitle => _useSavedDestinations
      ? 'Each of those keeps it.'
      : 'Send everything to one destination instead.';

  String get _dateText => DateFormat('MMMM d, yyyy').format(_date);

  /// Installment payments can't be dated in the future; the rest allow a
  /// planned date.
  DateTime get _lastDate =>
      _kind == SettleKind.installment ? DateTime.now() : DateTime(2030);

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.payers,
      selectedId: _accountId,
    );
    if (choice == null || choice.id == null) return;
    setState(() {
      _accountId = choice.id;
      // Can't transfer into the account the money left: ask again.
      if (_destinationId != null && _destinationId == _accountId) {
        _destinationId = null;
        _destinationChosen = false;
      }
    });
  }

  Future<void> _pickDestination() async {
    final choice = await showAccountPicker(
      context,
      accounts: _destinationOptions,
      selectedId: _destinationChosen ? _destinationId : null,
      allowNone: true,
      noneLabel: 'Spend it (no transfer)',
    );
    if (choice == null) return;
    setState(() {
      _destinationId = choice.id;
      _destinationChosen = true;
    });
  }

  Future<void> _pickDate() async {
    final last = _lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(last) ? last : _date,
      firstDate: DateTime(2020),
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _onAmountChanged(String _) => setState(() => _amountError = null);

  void _setAlreadyInLedger(bool? v) =>
      setState(() => _alreadyInLedger = v ?? false);

  void _setUseSavedDestinations(bool? v) =>
      setState(() => _useSavedDestinations = v ?? false);

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    final double amount;
    if (_isBatch) {
      amount = _copy.total;
    } else {
      final typed = parseSettleAmount(_amountController.text);
      final error = settleAmountError(
        amount: typed,
        kind: _kind,
        scheduled: _single.amount,
      );
      if (error != null) {
        setState(() => _amountError = error);
        return;
      }
      amount = typed!;
    }
    final result = SettleResult(
      amount: amount,
      date: _date,
      scheduledAmount: _isBatch ? _copy.total : _single.amount,
      accountId: _asksAccount ? _accountId : null,
      destinationId: _isSetAside ? _destinationId : null,
      recordInLedger: _recordsInLedger,
      useSavedDestinations: _useSavedDestinations,
      targetIds: [for (final t in widget.targets) t.id],
    );
    setState(() => _submitting = true);
    try {
      await widget.onConfirm(result);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      // Keep the sheet open with the values intact so the entry is not lost;
      // say why it failed.
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.error(context, 'Could not save: $e');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final copy = _copy;
    final shortNote = _shortBalanceNote;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            SheetTitle(copy.title),
            const SizedBox(height: 6),
            Text(
              copy.subtitle,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            ),
            if (_isBatch) ...[
              const SizedBox(height: 12),
              _BatchRows(targets: widget.targets),
            ],
            if (_showsAmount) ...[
              const SizedBox(height: 16),
              AppTextField(
                key: SettleSheetKeys.amount,
                controller: _amountController,
                label: copy.amountLabel,
                prefix: const Text('₱ '),
                errorText: _amountError,
                enabled: !_submitting,
                onChanged: _onAmountChanged,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
            if (_showsAccountPicker) ...[
              const SizedBox(height: 12),
              SheetFieldLabel(copy.accountLabel),
              SheetAccountField(
                key: SettleSheetKeys.account,
                account: _account,
                onTap: _pickAccount,
              ),
              if (shortNote != null) _ShortBalanceNote(message: shortNote),
            ],
            if (_showsNoPayers) ...[
              const SizedBox(height: 12),
              Text(
                _noPayersMessage,
                style: TextStyle(color: cs.error, fontSize: 12.5),
              ),
            ],
            if (_showsSavedDestinationToggle) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _useSavedDestinations,
                onChanged: _submitting ? null : _setUseSavedDestinations,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(_savedDestinationTitle),
                subtitle: Text(_savedDestinationSubtitle),
              ),
            ],
            if (_asksDestination) ...[
              const SizedBox(height: 12),
              SheetFieldLabel(_destinationLabel),
              SheetAccountField(
                key: SettleSheetKeys.destination,
                account: _destination,
                placeholder: _destinationPlaceholder,
                onTap: _pickDestination,
              ),
            ],
            const SizedBox(height: 12),
            SheetFieldLabel(copy.dateLabel),
            SheetPickerBox(
              key: SettleSheetKeys.date,
              onTap: _pickDate,
              trailingIcon: Icons.calendar_today_outlined,
              child: Text(
                _dateText,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
            ),
            if (_offersLedgerToggle) ...[
              const SizedBox(height: 12),
              AppFold(
                title: 'More options',
                subtitle: 'Already added to ledger',
                initiallyOpen: _alreadyInLedger,
                child: CheckboxListTile(
                  key: SettleSheetKeys.alreadyLogged,
                  value: _alreadyInLedger,
                  onChanged: _submitting ? null : _setAlreadyInLedger,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Already added to ledger'),
                  subtitle: Text(copy.alreadyLoggedSubtitle),
                ),
              ),
            ],
            const SizedBox(height: 20),
            AppPrimaryButton(
              key: SettleSheetKeys.confirm,
              label: copy.confirmLabel,
              onPressed: _canConfirm ? _confirm : null,
              isLoading: _submitting,
            ),
          ],
        ),
      ),
    );
  }
}

/// The short-balance note under the account picker. Named, never blocking.
class _ShortBalanceNote extends StatelessWidget {
  final String message;

  const _ShortBalanceNote({required this.message});

  @override
  Widget build(BuildContext context) {
    final warning = context.appColors.bills;
    return Padding(
      key: SettleSheetKeys.shortBalance,
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: warning, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rows of a batch: name, date, amount — read-only, so the user can see
/// what "Mark 3 paid" covers before confirming. A card on a sheet, so it sits
/// on `surfaceContainerHigh`.
class _BatchRows extends StatelessWidget {
  final List<SettleTarget> targets;

  const _BatchRows({required this.targets});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: SettleSheetKeys.batchRows,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: targets.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
          itemBuilder: (context, i) => _BatchRow(target: targets[i]),
        ),
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  final SettleTarget target;

  const _BatchRow({required this.target});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateLabel = target.dateLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              target.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (dateLabel != null) ...[
            const SizedBox(width: 8),
            Text(
              dateLabel,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            formatPeso(target.amount),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
