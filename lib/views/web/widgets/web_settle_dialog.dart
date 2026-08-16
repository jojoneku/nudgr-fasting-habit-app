import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../design/web_breakpoints.dart';

final _dateFmt = DateFormat('MMMM d, yyyy');

/// Sentinel for the destination dropdown's "spend it, don't transfer" option.
/// Null is a *real* answer there, so it can't double as "nothing picked yet".
const _spendItSentinel = '__spend__';

/// What the user settled on. Handed to [showWebSettleDialog]'s `onSubmit`, and
/// returned to the caller once that submit succeeds so the toast can quote the
/// amount that was actually recorded rather than the one that was scheduled.
class WebSettleResult {
  /// The amount actually settled — may be a partial payment or an overpayment,
  /// which is the whole reason this dialog exists.
  final double amount;

  /// What the entry said it would be, kept so callers can tell a deliberate
  /// partial payment from the scheduled figure.
  final double? scheduledAmount;

  /// When it happened. Defaults to today but is freely back-datable, so last
  /// month's bills can be reconciled from a desktop.
  final DateTime date;

  /// Funding (or destination, for an inflow) account. Null when the flow has no
  /// account picker, or when [recordInLedger] is false.
  final String? accountId;

  /// Second account for set-asides — where the money lands. Null means "spend
  /// it" (a plain outflow rather than a transfer).
  final String? destinationId;

  /// False when the user already logged the movement in the ledger by hand, so
  /// the entry is flagged settled without creating a transaction.
  final bool recordInLedger;

  const WebSettleResult({
    required this.amount,
    required this.date,
    this.scheduledAmount,
    this.accountId,
    this.destinationId,
    this.recordInLedger = true,
  });

  /// True when the settled amount differs from what was scheduled — the callers
  /// use it to word the confirmation toast honestly.
  bool get isPartial =>
      scheduledAmount != null && amount < scheduledAmount! - 0.005;
  bool get isOverpayment =>
      scheduledAmount != null && amount > scheduledAmount! + 0.005;
}

/// Configures the optional second account picker (set-aside destinations).
/// Absent for every other flow.
class WebSettleDestination {
  final List<FinancialAccount> options;
  final String label;
  final String hint;
  final String spendItLabel;
  final String? initialId;

  /// Whether [initialId] counts as a deliberate choice. A set-aside with no
  /// destination on file starts unchosen, so Fund waits for an answer instead
  /// of silently picking a savings account the user never named.
  final bool initiallyChosen;

  const WebSettleDestination({
    required this.options,
    required this.label,
    this.hint = 'Choose where it goes',
    this.spendItLabel = 'Spend it (no transfer)',
    this.initialId,
    this.initiallyChosen = false,
  });
}

/// The one settle dialog behind every desktop "this is now paid / received /
/// funded" action: bills, receivables, set-asides and installments.
///
/// Each of those used to be its own `AlertDialog` that settled the scheduled
/// amount, dated today, with no way to say otherwise — so a partial payment, an
/// overpayment, or reconciling last month could only be done on the phone.
/// Every one of them now goes through here and gets the mobile contract: an
/// editable amount, a date picker, and (where the flow has one) an account
/// picker. It is the desktop sibling of the mobile settle sheets, and follows
/// the same shape as [showWebQuickPayDialog].
///
/// [onSubmit] performs the write. Errors keep the dialog open with the values
/// intact so the user can correct and retry, rather than dropping the entry
/// silently un-settled. Returns the settled values, or null if cancelled.
Future<WebSettleResult?> showWebSettleDialog(
  BuildContext context, {
  required String title,
  required String summary,
  required String confirmLabel,
  required double initialAmount,
  required Future<void> Function(WebSettleResult) onSubmit,
  String amountLabel = 'Amount',
  String dateLabel = 'Date',
  String? scheduledNote,
  List<FinancialAccount> accounts = const [],
  String accountLabel = 'Pay from',
  String? initialAccountId,
  bool requiresAccount = false,
  bool showLedgerToggle = false,
  String ledgerToggleLabel = 'Already added to ledger',
  String? emptyAccountsMessage,
  WebSettleDestination? destination,
}) {
  return showDialog<WebSettleResult>(
    context: context,
    builder: (_) => _WebSettleDialog(
      title: title,
      summary: summary,
      confirmLabel: confirmLabel,
      initialAmount: initialAmount,
      onSubmit: onSubmit,
      amountLabel: amountLabel,
      dateLabel: dateLabel,
      scheduledNote: scheduledNote,
      accounts: accounts,
      accountLabel: accountLabel,
      initialAccountId: initialAccountId,
      requiresAccount: requiresAccount,
      showLedgerToggle: showLedgerToggle,
      ledgerToggleLabel: ledgerToggleLabel,
      emptyAccountsMessage: emptyAccountsMessage,
      destination: destination,
    ),
  );
}

class _WebSettleDialog extends StatefulWidget {
  final String title;
  final String summary;
  final String confirmLabel;
  final double initialAmount;
  final Future<void> Function(WebSettleResult) onSubmit;
  final String amountLabel;
  final String dateLabel;
  final String? scheduledNote;
  final List<FinancialAccount> accounts;
  final String accountLabel;
  final String? initialAccountId;
  final bool requiresAccount;
  final bool showLedgerToggle;
  final String ledgerToggleLabel;
  final String? emptyAccountsMessage;
  final WebSettleDestination? destination;

  const _WebSettleDialog({
    required this.title,
    required this.summary,
    required this.confirmLabel,
    required this.initialAmount,
    required this.onSubmit,
    required this.amountLabel,
    required this.dateLabel,
    required this.scheduledNote,
    required this.accounts,
    required this.accountLabel,
    required this.initialAccountId,
    required this.requiresAccount,
    required this.showLedgerToggle,
    required this.ledgerToggleLabel,
    required this.emptyAccountsMessage,
    required this.destination,
  });

  @override
  State<_WebSettleDialog> createState() => _WebSettleDialogState();
}

class _WebSettleDialogState extends State<_WebSettleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  String? _accountId;
  String? _destinationId;
  late bool _destinationChosen;
  DateTime _date = DateTime.now();
  bool _alreadyInLedger = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: widget.initialAmount.toStringAsFixed(2));
    // Only honour a preselection the picker can actually show — a dropdown
    // whose value isn't among its items asserts at build time.
    final preselected = widget.initialAccountId;
    _accountId = widget.accounts.any((a) => a.id == preselected)
        ? preselected
        : widget.accounts.firstOrNull?.id;
    // Same guard for the destination: it must be an offered option, and it can
    // never be the funding account (money can't move into the account it left).
    final destination = widget.destination;
    final wanted = destination?.initialId;
    _destinationId = wanted != null &&
            wanted != _accountId &&
            (destination?.options.any((a) => a.id == wanted) ?? false)
        ? wanted
        : null;
    // "Spend it" is a real answer, so an explicitly-chosen null still counts as
    // chosen; only a dropped preselection reopens the question.
    _destinationChosen = destination == null ||
        (destination.initiallyChosen && _destinationId != null);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// Destinations minus the funding account — money can't be transferred into
  /// the account it just left.
  List<FinancialAccount> get _destinationOptions => [
        for (final a
            in widget.destination?.options ?? const <FinancialAccount>[])
          if (a.id != _accountId) a,
      ];

  /// Whether this settle is going to write a ledger entry. False once the user
  /// says they already logged it by hand, which is what makes the account
  /// optional rather than required.
  bool get _recordsInLedger => !(widget.showLedgerToggle && _alreadyInLedger);

  bool get _canSubmit {
    if (_isSubmitting) return false;
    // Blocks the "no eligible accounts" case too: the picker has nothing to
    // offer, so _accountId stays null and the write would fail downstream.
    if (widget.requiresAccount && _recordsInLedger && _accountId == null) {
      return false;
    }
    // Where the money goes has to be settled before it moves.
    if (widget.destination != null && !_destinationChosen) return false;
    return true;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount =
        double.parse(_amountController.text.replaceAll(',', '').trim());
    final recordInLedger = _recordsInLedger;
    final result = WebSettleResult(
      amount: amount,
      date: _date,
      scheduledAmount: widget.initialAmount,
      accountId: recordInLedger ? _accountId : null,
      destinationId: _destinationId,
      recordInLedger: recordInLedger,
    );

    setState(() => _isSubmitting = true);
    try {
      await widget.onSubmit(result);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      // Keep the dialog open with the values intact — a failed write used to
      // leave the entry silently un-settled with nothing on screen to say so.
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppToast.error(
            context, 'Could not ${widget.confirmLabel.toLowerCase()}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final destination = widget.destination;
    final destinationOptions = _destinationOptions;
    final showAccountPicker = widget.accounts.isNotEmpty && _recordsInLedger;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.summary,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: WebInsets.lg),
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: widget.amountLabel,
                  prefixText: '₱ ',
                  // Naming the scheduled figure is what makes a deliberate
                  // partial payment distinguishable from a typo.
                  helperText: widget.scheduledNote ??
                      'Scheduled: ${formatPeso(widget.initialAmount)}',
                ),
                validator: (v) {
                  final amount =
                      double.tryParse((v ?? '').replaceAll(',', '').trim());
                  if (amount == null || amount <= 0) return 'Enter an amount';
                  if (!amount.isFinite) return 'Enter an amount';
                  return null;
                },
              ),
              if (showAccountPicker) ...[
                const SizedBox(height: WebInsets.lg),
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: InputDecoration(labelText: widget.accountLabel),
                  items: [
                    for (final a in widget.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} · ${formatPeso(a.balance)}'),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _accountId = v ?? _accountId;
                    // Can't transfer into the account the money just left.
                    if (_destinationId == _accountId) _destinationId = null;
                  }),
                ),
              ],
              if (destination != null && _recordsInLedger) ...[
                const SizedBox(height: WebInsets.lg),
                DropdownButtonFormField<String>(
                  initialValue: _destinationChosen
                      ? (_destinationId ?? _spendItSentinel)
                      : null,
                  decoration: InputDecoration(
                    labelText: destination.label,
                    hintText: destination.hint,
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: _spendItSentinel,
                      child: Text(destination.spendItLabel),
                    ),
                    for (final a in destinationOptions)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _destinationId = v == _spendItSentinel ? null : v;
                    _destinationChosen = true;
                  }),
                ),
              ],
              const SizedBox(height: WebInsets.lg),
              InputDecorator(
                decoration: InputDecoration(labelText: widget.dateLabel),
                child: InkWell(
                  onTap: _isSubmitting ? null : _pickDate,
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: WebInsets.sm),
                      Text(_dateFmt.format(_date),
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
              if (widget.showLedgerToggle) ...[
                const SizedBox(height: WebInsets.xs),
                CheckboxListTile(
                  value: _alreadyInLedger,
                  onChanged: _isSubmitting
                      ? null
                      : (v) => setState(() => _alreadyInLedger = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(widget.ledgerToggleLabel),
                ),
              ],
              if (widget.accounts.isEmpty &&
                  widget.emptyAccountsMessage != null) ...[
                const SizedBox(height: WebInsets.md),
                Text(
                  widget.emptyAccountsMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
