import 'package:flutter/material.dart';

import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/utils/settle_copy.dart';
import 'package:intermittent_fasting/utils/settle_rules.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../design/web_breakpoints.dart';
import '../web_keys.dart';
import 'web_dialog.dart';
import 'web_form_controls.dart';
import 'web_number.dart';

/// Sentinel for the destination dropdown's "spend it, don't transfer" option.
/// Null is a *real* answer there, so it can't double as "nothing picked yet".
const _spendItSentinel = '__spend__';

/// The pre-unification name, kept so the old pages and tests read unchanged.
typedef WebSettleResult = SettleResult;

/// The one settle dialog behind every desktop "this is now paid / received /
/// funded" action (Plan 063 §5): bills, receivables, set-asides, installments
/// and card payments; one row or a batch.
///
/// Single mode (one target) asks for the amount (editable — a partial payment,
/// an overpayment, a rounded final installment), the date, and where the money
/// moves. Batch mode (several targets) lists the rows and asks once for what
/// they share: the account and the date; each row settles for its own full
/// amount.
///
/// [accounts] are the eligible funding (or deposit) accounts; the picker is
/// skipped for [SettleKind.installment], which rides on its own card. A short
/// balance is named under the picker but does not block. [destinations] and
/// [savedDestinationCount] drive the set-aside "Set aside into" question.
///
/// With [onSubmit], the dialog performs the write and stays open with the
/// values intact if it throws, so a failed write never leaves the entry
/// silently un-settled. Without it, the dialog returns the user's choice and
/// the caller runs the write (the batch call sites, which report partial
/// results themselves). Returns null when cancelled.
Future<SettleResult?> showWebSettleDialog(
  BuildContext context, {
  required SettleKind kind,
  required List<SettleTarget> targets,
  required List<FinancialAccount> accounts,
  Future<void> Function(SettleResult result)? onSubmit,
  String? initialAccountId,
  List<FinancialAccount> destinations = const [],
  int savedDestinationCount = 0,
  bool requiresAccount = true,
  String? emptyAccountsMessage,
}) {
  assert(targets.isNotEmpty, 'Settle needs at least one target');
  return showWebDialog<SettleResult>(
    context,
    builder: (_) => _WebSettleDialog(
      kind: kind,
      targets: targets,
      accounts: accounts,
      onSubmit: onSubmit,
      initialAccountId: initialAccountId,
      destinations: destinations,
      savedDestinationCount: savedDestinationCount,
      requiresAccount: requiresAccount,
      emptyAccountsMessage: emptyAccountsMessage,
    ),
  );
}

/// Batch entry point kept for the pre-v2 Bills page: the same signature the
/// old batch dialog had, delegating to [showWebSettleDialog] in batch mode and
/// handing back the [BatchSettleChoice] its call sites consume.
///
/// Pass [targets] to list the rows; without them the dialog shows the count
/// and total only.
Future<BatchSettleChoice?> showWebBatchSettleDialog(
  BuildContext context, {
  required BatchSettleKind kind,
  required int count,
  required double total,
  List<FinancialAccount> accounts = const [],
  List<FinancialAccount> destinations = const [],
  String? initialAccountId,
  int savedDestinationCount = 0,
  List<SettleTarget>? targets,
}) async {
  final settleKind = switch (kind) {
    BatchSettleKind.bills => SettleKind.bill,
    BatchSettleKind.receivables => SettleKind.receivable,
    BatchSettleKind.setAsides => SettleKind.setAside,
    BatchSettleKind.installments => SettleKind.installment,
  };
  final rows = targets ??
      [
        // Unnamed stand-ins: the dialog lists rows only when they carry names.
        for (var i = 0; i < count; i++)
          SettleTarget(
            id: '#$i',
            name: '',
            amount: count == 0 ? 0 : total / count,
          ),
      ];
  final result = await showWebDialog<SettleResult>(
    context,
    builder: (_) => _WebSettleDialog(
      kind: settleKind,
      targets: rows,
      accounts: accounts,
      onSubmit: null,
      initialAccountId: initialAccountId,
      destinations: destinations,
      savedDestinationCount: savedDestinationCount,
      requiresAccount: false,
      emptyAccountsMessage: null,
      // A batch of one is still a batch: the bar's "Pay 1" settles the row
      // for its full amount, as the old batch dialog did.
      forceBatch: true,
    ),
  );
  return result?.toBatchChoice();
}

/// Card-payment entry point kept for the Dashboard: pays [card] from any
/// active non-liability account through [SettleKind.cardPayment], performing
/// the write via `presenter.quickPayCard`. Returns the amount paid, or null.
Future<double?> showWebQuickPayDialog(
  BuildContext context, {
  required FinancialAccount card,
  required BillsReceivablesPresenter presenter,
}) async {
  final payers = presenter.cardPayerAccounts;
  final result = await showWebSettleDialog(
    context,
    kind: SettleKind.cardPayment,
    targets: [
      SettleTarget(id: card.id, name: card.name, amount: card.currentPayable),
    ],
    accounts: payers,
    emptyAccountsMessage: 'No liquid accounts available.',
    onSubmit: (r) => presenter.quickPayCard(
      accountId: card.id,
      fromAccountId: r.accountId!,
      amount: r.amount,
      date: r.date,
    ),
  );
  return result?.amount;
}

class _WebSettleDialog extends StatefulWidget {
  final SettleKind kind;
  final List<SettleTarget> targets;
  final List<FinancialAccount> accounts;
  final Future<void> Function(SettleResult result)? onSubmit;
  final String? initialAccountId;
  final List<FinancialAccount> destinations;
  final int savedDestinationCount;
  final bool requiresAccount;
  final String? emptyAccountsMessage;

  /// Batch mode regardless of how many rows there are (the pre-v2 wrapper).
  final bool forceBatch;

  const _WebSettleDialog({
    required this.kind,
    required this.targets,
    required this.accounts,
    required this.onSubmit,
    required this.initialAccountId,
    required this.destinations,
    required this.savedDestinationCount,
    required this.requiresAccount,
    required this.emptyAccountsMessage,
    this.forceBatch = false,
  });

  @override
  State<_WebSettleDialog> createState() => _WebSettleDialogState();
}

class _WebSettleDialogState extends State<_WebSettleDialog> {
  late final TextEditingController _amountController;
  String? _amountError;
  String? _accountId;
  String? _destinationId;
  late bool _destinationChosen;
  bool _useSavedDestinations = true;
  DateTime _date = DateTime.now();
  bool _alreadyInLedger = false;
  bool _isSubmitting = false;

  SettleKind get _kind => widget.kind;
  bool get _isBatch => widget.forceBatch || widget.targets.length > 1;
  SettleTarget get _single => widget.targets.first;
  int get _count => widget.targets.length;
  double get _total => widget.targets.fold(0.0, (s, t) => s + t.amount);

  /// Rows are listed only when they carry names — the pre-v2 wrapper passes
  /// unnamed stand-ins.
  bool get _listsRows =>
      _isBatch && widget.targets.every((t) => t.name.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: _single.amount.toStringAsFixed(2));
    // Only honour a preselection the picker can actually show — a dropdown
    // whose value isn't among its items asserts at build time.
    final wanted =
        widget.initialAccountId ?? (_isBatch ? null : _single.accountId);
    _accountId = widget.accounts.any((a) => a.id == wanted)
        ? wanted
        : widget.accounts.firstOrNull?.id;
    // Same guard for the destination: it must be on offer, and it can never be
    // the funding account (money can't move into the account it left).
    final onFile = _isBatch ? null : _single.destinationId;
    _destinationId = onFile != null &&
            onFile != _accountId &&
            widget.destinations.any((a) => a.id == onFile)
        ? onFile
        : null;
    // "Spend it" is a real answer, so only a set-aside with nothing on file
    // (or a dropped preselection) starts with the question open.
    _destinationChosen = _kind != SettleKind.setAside || _destinationId != null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // ── What this kind asks for ───────────────────────────────────────────────

  /// Bills and receivables can be flagged settled without writing the ledger.
  /// A set-aside *is* the transfer, an installment payment IS its transaction
  /// and a card payment is a transfer, so none of those offers the choice.
  bool get _offersLedgerToggle => settleOffersLedgerToggle(_kind);

  bool get _recordsInLedger => !(_offersLedgerToggle && _alreadyInLedger);

  /// Installments ride on their own card, so there is nothing to pick.
  bool get _asksAccount =>
      settleAsksAccount(_kind, recordInLedger: _recordsInLedger);

  bool get _isSetAside => _kind == SettleKind.setAside;

  /// Batch set-asides: rows with no destination of their own, which the shared
  /// destination applies to.
  int get _unnamedDestinations => !_isBatch
      ? 1
      : _useSavedDestinations
          ? _count - widget.savedDestinationCount
          : _count;

  bool get _asksDestination =>
      _isSetAside && _recordsInLedger && _unnamedDestinations > 0;

  List<FinancialAccount> get _destinationOptions => [
        for (final a in widget.destinations)
          if (a.id != _accountId) a,
      ];

  FinancialAccount? get _funder =>
      widget.accounts.where((a) => a.id == _accountId).firstOrNull;

  double? get _typedAmount => parseSettleAmount(_amountController.text);

  /// The figure that will leave (or enter) the account.
  double get _movingAmount => _isBatch ? _total : (_typedAmount ?? 0);

  /// Named, never blocking: the user may be about to move money in first.
  /// Receivables deposit money, so there is nothing to be short of.
  String? get _shortBalanceNote => !_asksAccount
      ? null
      : settleShortBalanceNote(
          kind: _kind,
          amount: _movingAmount,
          from: _funder,
        );

  bool get _canSubmit {
    if (_isSubmitting) return false;
    // Single mode blocks the "no eligible accounts" case: the picker has
    // nothing to offer, so the write would fail downstream. A batch goes
    // through flagged settled without a ledger entry instead.
    if (!_isBatch &&
        widget.requiresAccount &&
        _asksAccount &&
        _accountId == null) {
      return false;
    }
    if (_asksDestination && !_destinationChosen) return false;
    return true;
  }

  // ── Copy ─────────────────────────────────────────────────────────────────

  SettleCopy get _copy =>
      SettleCopy(kind: _kind, targets: widget.targets, isBatch: _isBatch);

  String get _title => _copy.title;
  String get _subtitle => _copy.subtitle;
  String get _amountLabel => _copy.amountLabel;
  String get _dateLabel => _copy.dateLabel;
  String get _accountLabel => _copy.accountLabel;
  String get _confirmLabel => _copy.confirmLabel;
  String get _failureVerb => _copy.failureVerb;

  // ── Actions ──────────────────────────────────────────────────────────────

  String? _validateAmount(double? amount) => settleAmountError(
        amount: amount,
        kind: _kind,
        scheduled: _single.amount,
      );

  Future<void> _submit() async {
    final double amount;
    if (_isBatch) {
      amount = _total;
    } else {
      final typed = _typedAmount;
      final error = _validateAmount(typed);
      if (error != null) {
        setState(() => _amountError = error);
        return;
      }
      amount = typed!;
    }
    final recordInLedger = _recordsInLedger;
    final result = SettleResult(
      amount: amount,
      date: _date,
      scheduledAmount: _isBatch ? _total : _single.amount,
      accountId: _asksAccount ? _accountId : null,
      destinationId: _isSetAside ? _destinationId : null,
      recordInLedger: recordInLedger,
      useSavedDestinations: _useSavedDestinations,
      targetIds: [for (final t in widget.targets) t.id],
    );

    final onSubmit = widget.onSubmit;
    if (onSubmit == null) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await onSubmit(result);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      // Keep the dialog open with the values intact — a failed write used to
      // leave the entry silently un-settled with nothing on screen to say so.
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppToast.error(context, 'Could not $_failureVerb: $e');
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = context.appColors.bills;
    final showAccountPicker = _asksAccount && widget.accounts.isNotEmpty;
    final shortNote = _shortBalanceNote;

    final (Color primaryBg, Color primaryFg) = switch (_kind) {
      SettleKind.receivable => (cs.tertiary, cs.onTertiary),
      SettleKind.setAside => (cs.primary, cs.onPrimary),
      _ => (warning, cs.surface),
    };

    final dateField = WebField(
      label: _dateLabel,
      child: WebDateButton(
        key: WebKeys.billsSettleDate,
        value: _date,
        onChanged: _isSubmitting ? null : (d) => setState(() => _date = d),
      ),
    );

    return WebDialog(
      title: _title,
      subtitle: _subtitle,
      onSubmit: _canSubmit ? _submit : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_listsRows) ...[
            _BatchRows(targets: widget.targets),
            const SizedBox(height: WebInsets.lg),
          ],
          // The canvas pairs the amount with the date on one row; a batch
          // has no amount of its own, so the date takes the row alone.
          if (_isBatch)
            dateField
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: WebField(
                    label: _amountLabel,
                    error: _amountError,
                    child: WebInput.amount(
                      key: WebKeys.billsSettleAmount,
                      controller: _amountController,
                      autofocus: true,
                      enabled: !_isSubmitting,
                      error: _amountError != null,
                      onChanged: (_) => setState(() => _amountError = null),
                    ),
                  ),
                ),
                const SizedBox(width: WebInsets.md),
                Expanded(child: dateField),
              ],
            ),
          if (showAccountPicker) ...[
            const SizedBox(height: 14),
            WebField(
              label: _accountLabel,
              child: WebDropdown<String>(
                key: WebKeys.billsSettleAccount,
                value: _accountId,
                items: [
                  for (final a in widget.accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} · ${formatPeso(a.balance)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _isSubmitting
                    ? null
                    : (v) => setState(() {
                          _accountId = v ?? _accountId;
                          // Can't transfer into the account the money left.
                          if (_destinationId == _accountId) {
                            _destinationId = null;
                            _destinationChosen = false;
                          }
                        }),
              ),
            ),
            if (shortNote != null)
              WebFieldWarning(message: shortNote, color: warning),
          ],
          if (_asksAccount && widget.accounts.isEmpty) ...[
            const SizedBox(height: 14),
            Text(
              _isBatch
                  ? 'No account can cover this whole selection. They will be '
                      'flagged settled without a ledger entry.'
                  : widget.emptyAccountsMessage ??
                      'Add an account before settling.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _isBatch ? warning : cs.error,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (_isSetAside && _isBatch && widget.savedDestinationCount > 0) ...[
            const SizedBox(height: 14),
            WebSwitchRow(
              title: '${widget.savedDestinationCount} of $_count have their '
                  'own destination',
              subtitle: _useSavedDestinations
                  ? 'Each of those keeps it.'
                  : 'Send everything to one destination instead.',
              value: _useSavedDestinations,
              onChanged: _isSubmitting
                  ? null
                  : (v) => setState(() => _useSavedDestinations = v),
            ),
          ],
          if (_asksDestination) ...[
            const SizedBox(height: 14),
            WebField(
              label: _isBatch &&
                      widget.savedDestinationCount > 0 &&
                      _useSavedDestinations
                  ? 'Set the other $_unnamedDestinations aside into'
                  : 'Set aside into',
              helper: _destinationChosen ? null : 'Choose where it goes',
              child: WebDropdown<String>(
                // Re-created when the funding account changes, so a reset
                // destination is really blank rather than a stale value.
                key: ValueKey('${WebKeys.billsSettleDestination.value}:'
                    '$_accountId'),
                value: _destinationChosen
                    ? (_destinationId ?? _spendItSentinel)
                    : null,
                hint: 'Choose where it goes',
                items: [
                  const DropdownMenuItem<String>(
                    value: _spendItSentinel,
                    child: Text('Spend it (no transfer)'),
                  ),
                  for (final a in _destinationOptions)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: _isSubmitting
                    ? null
                    : (v) => setState(() {
                          _destinationId = v == _spendItSentinel ? null : v;
                          _destinationChosen = true;
                        }),
              ),
            ),
          ],
          if (_offersLedgerToggle) ...[
            const SizedBox(height: 14),
            WebSwitchRow(
              key: WebKeys.billsSettleAlreadyLogged,
              title: 'Already in the ledger',
              subtitle: _copy.alreadyLoggedSubtitle,
              value: _alreadyInLedger,
              onChanged: _isSubmitting
                  ? null
                  : (v) => setState(() => _alreadyInLedger = v),
            ),
          ],
        ],
      ),
      secondary: TextButton(
        key: WebKeys.billsSettleCancel,
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton(
        key: WebKeys.billsSettleConfirm,
        style: FilledButton.styleFrom(
          backgroundColor: primaryBg,
          foregroundColor: primaryFg,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: _canSubmit ? _submit : null,
        child: _isSubmitting
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primaryFg,
                ),
              )
            : Text(_confirmLabel),
      ),
    );
  }
}

/// The rows of a batch: name, date, amount — read-only, so the user can see
/// what "Pay 2" covers before confirming.
class _BatchRows extends StatelessWidget {
  final List<SettleTarget> targets;

  const _BatchRows({required this.targets});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.55),
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(14),
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
            color: cs.outlineVariant.withValues(alpha: 0.6),
          ),
          itemBuilder: (context, i) {
            final t = targets[i];
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (t.dateLabel != null) ...[
                    const SizedBox(width: WebInsets.sm),
                    Text(
                      t.dateLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(width: WebInsets.md),
                  Text(
                    formatPeso(t.amount),
                    style: webNumericStyle(
                      theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
