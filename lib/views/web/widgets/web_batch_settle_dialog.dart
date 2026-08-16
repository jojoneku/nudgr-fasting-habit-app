import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/bills/batch_settle_sheet.dart';
import '../design/web_breakpoints.dart';

final _dateFmt = DateFormat('MMMM d, yyyy');

/// Sentinel for "spend it" in the destination dropdown — null is a real answer
/// there, so it can't double as "nothing picked yet".
const _spendItSentinel = '__spend__';

/// Desktop counterpart of the mobile [showBatchSettleSheet], deliberately built
/// on the same [BatchSettleKind] / [BatchSettleChoice] types so the two
/// platforms can't drift on what a batch means.
///
/// Like mobile, every selected row settles for its own full amount — a batch is
/// for "these all happened", not for editing figures, which is what the
/// single-row settle dialog is for. What the batch shares is asked once: the
/// account the money moves through, and the date.
///
/// Returns null when cancelled.
Future<BatchSettleChoice?> showWebBatchSettleDialog(
  BuildContext context, {
  required BatchSettleKind kind,
  required int count,
  required double total,
  List<FinancialAccount> accounts = const [],
  List<FinancialAccount> destinations = const [],
  String? initialAccountId,
  int savedDestinationCount = 0,
}) {
  return showDialog<BatchSettleChoice>(
    context: context,
    builder: (_) => _WebBatchSettleDialog(
      kind: kind,
      count: count,
      total: total,
      accounts: accounts,
      destinations: destinations,
      initialAccountId: initialAccountId,
      savedDestinationCount: savedDestinationCount,
    ),
  );
}

class _WebBatchSettleDialog extends StatefulWidget {
  final BatchSettleKind kind;
  final int count;
  final double total;
  final List<FinancialAccount> accounts;
  final List<FinancialAccount> destinations;
  final String? initialAccountId;
  final int savedDestinationCount;

  const _WebBatchSettleDialog({
    required this.kind,
    required this.count,
    required this.total,
    required this.accounts,
    required this.destinations,
    required this.initialAccountId,
    required this.savedDestinationCount,
  });

  @override
  State<_WebBatchSettleDialog> createState() => _WebBatchSettleDialogState();
}

class _WebBatchSettleDialogState extends State<_WebBatchSettleDialog> {
  String? _accountId;
  String? _toAccountId;
  bool _destinationChosen = false;
  bool _useSavedDestinations = true;
  bool _alreadyInLedger = false;
  DateTime _date = DateTime.now();

  bool get _isSetAside => widget.kind == BatchSettleKind.setAsides;

  /// Installments each carry their own account, so the dialog asks for none.
  bool get _needsAccount =>
      widget.kind != BatchSettleKind.installments && !_alreadyInLedger;

  /// Bills and receivables can be flagged settled without writing the ledger.
  /// A set-aside *is* the transfer and an installment payment IS its
  /// transaction, so neither offers the choice.
  bool get _offersLedgerOptOut =>
      widget.kind == BatchSettleKind.bills ||
      widget.kind == BatchSettleKind.receivables;

  /// Rows with no destination of their own — the ones the shared destination
  /// applies to.
  int get _unnamedDestinations => _useSavedDestinations
      ? widget.count - widget.savedDestinationCount
      : widget.count;

  bool get _needsDestination => _isSetAside && _unnamedDestinations > 0;

  List<FinancialAccount> get _destinationOptions => [
        for (final a in widget.destinations)
          if (a.id != _accountId) a
      ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialAccountId;
    _accountId = initial != null && widget.accounts.any((a) => a.id == initial)
        ? initial
        : (widget.accounts.isNotEmpty ? widget.accounts.first.id : null);
  }

  String get _title => switch (widget.kind) {
        BatchSettleKind.bills => 'Mark ${widget.count} bills paid',
        BatchSettleKind.receivables => 'Mark ${widget.count} received',
        BatchSettleKind.setAsides => 'Fund ${widget.count} set-asides',
        BatchSettleKind.installments => 'Pay ${widget.count} installments',
      };

  String get _subtitle => switch (widget.kind) {
        BatchSettleKind.bills =>
          '${formatPeso(widget.total)} leaves the account you pick. Each bill '
              'settles for its own full amount.',
        BatchSettleKind.receivables =>
          '${formatPeso(widget.total)} lands in the account you pick. Each one '
              'settles for its own full amount.',
        BatchSettleKind.setAsides =>
          '${formatPeso(widget.total)} moves out of the funding account. '
              'Setting money aside is a transfer, not spending.',
        BatchSettleKind.installments =>
          '${formatPeso(widget.total)} across this month\'s payments, each from '
              'its own account.',
      };

  String get _accountLabel => switch (widget.kind) {
        BatchSettleKind.receivables => 'Deposit into',
        BatchSettleKind.setAsides => 'Fund from',
        _ => 'Pay from',
      };

  String get _confirmLabel => switch (widget.kind) {
        BatchSettleKind.bills => 'Mark ${widget.count} paid',
        BatchSettleKind.receivables => 'Mark ${widget.count} received',
        BatchSettleKind.setAsides => 'Fund ${widget.count}',
        BatchSettleKind.installments => 'Pay ${widget.count}',
      };

  bool get _canConfirm {
    if (_needsAccount && widget.accounts.isNotEmpty && _accountId == null) {
      return false;
    }
    if (_needsDestination && !_destinationChosen) return false;
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

  void _confirm() {
    Navigator.of(context).pop(BatchSettleChoice(
      accountId: _needsAccount ? _accountId : null,
      toAccountId: _toAccountId,
      useSavedDestinations: _useSavedDestinations,
      alreadyInLedger: _alreadyInLedger,
      date: _date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final showAccount = _needsAccount && widget.accounts.isNotEmpty;

    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _subtitle,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (_offersLedgerOptOut) ...[
                const SizedBox(height: WebInsets.sm),
                CheckboxListTile(
                  value: _alreadyInLedger,
                  onChanged: (v) =>
                      setState(() => _alreadyInLedger = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Already added to ledger'),
                  subtitle: const Text(
                      "Just settle them — don't record transactions or touch "
                      'any balance.'),
                ),
              ],
              if (showAccount) ...[
                const SizedBox(height: WebInsets.lg),
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: InputDecoration(labelText: _accountLabel),
                  items: [
                    for (final a in widget.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} · ${formatPeso(a.balance)}'),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _accountId = v ?? _accountId;
                    // A set-aside can't be transferred into the account it
                    // came from.
                    if (_toAccountId == _accountId) _toAccountId = null;
                  }),
                ),
              ],
              if (_needsAccount && widget.accounts.isEmpty) ...[
                const SizedBox(height: WebInsets.md),
                Text(
                  'No account can cover this whole selection. They will be '
                  'flagged settled without a ledger entry.',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              ],
              if (_isSetAside) ...[
                if (widget.savedDestinationCount > 0) ...[
                  const SizedBox(height: WebInsets.sm),
                  CheckboxListTile(
                    value: _useSavedDestinations,
                    onChanged: (v) =>
                        setState(() => _useSavedDestinations = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('${widget.savedDestinationCount} of '
                        '${widget.count} have their own destination'),
                    subtitle: Text(_useSavedDestinations
                        ? 'Each of those keeps it.'
                        : 'Send everything to one destination instead.'),
                  ),
                ],
                if (_needsDestination) ...[
                  const SizedBox(height: WebInsets.lg),
                  DropdownButtonFormField<String>(
                    initialValue: _destinationChosen
                        ? (_toAccountId ?? _spendItSentinel)
                        : null,
                    decoration: InputDecoration(
                      labelText: widget.savedDestinationCount > 0 &&
                              _useSavedDestinations
                          ? 'Set the other $_unnamedDestinations aside into'
                          : 'Set aside into',
                      hintText: 'Choose where it goes',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: _spendItSentinel,
                        child: Text('Spend it (no transfer)'),
                      ),
                      for (final a in _destinationOptions)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _toAccountId = v == _spendItSentinel ? null : v;
                      _destinationChosen = true;
                    }),
                  ),
                ],
              ],
              const SizedBox(height: WebInsets.lg),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: InkWell(
                  onTap: _pickDate,
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canConfirm ? _confirm : null,
          child: Text(_confirmLabel),
        ),
      ],
    );
  }
}
