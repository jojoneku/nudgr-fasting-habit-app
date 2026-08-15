import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';

/// Which kind of obligation a batch is settling. Decides the sheet's wording and
/// which fields it asks for — the money moves differently for each.
enum BatchSettleKind { bills, receivables, setAsides, installments }

/// What the user agreed to in [showBatchSettleSheet]. Every selected row is
/// settled for its own full amount — a batch is for "these all happened", not
/// for editing figures, which is what the single-row sheets are for.
class BatchSettleChoice {
  /// Funding account (bills, set-asides) or deposit account (receivables).
  /// Null when [alreadyInLedger] is set, or for installments, which are each
  /// paid from their own account.
  final String? accountId;

  /// Set-aside destination applied to rows that don't carry one of their own.
  /// Null means "spend it" — a plain outflow, no transfer.
  final String? toAccountId;

  /// Let rows that already name a destination keep it, and apply
  /// [toAccountId] only to the rest.
  final bool useSavedDestinations;

  /// The user already logged these in the ledger by hand: flag them settled
  /// without writing transactions or touching balances.
  final bool alreadyInLedger;

  final DateTime date;

  const BatchSettleChoice({
    required this.accountId,
    required this.toAccountId,
    required this.useSavedDestinations,
    required this.alreadyInLedger,
    required this.date,
  });
}

/// Confirms settling several obligations at once, asking once for what the whole
/// batch shares: the account the money moves through and the date.
///
/// [savedDestinationCount] is how many of the selected set-asides already name a
/// destination account. Those keep it (unless the user says otherwise); the rest
/// need the one decision this sheet asks for — a destination is never guessed,
/// since money quietly parked in the wrong account is hard to notice.
///
/// Returns null when dismissed.
Future<BatchSettleChoice?> showBatchSettleSheet(
  BuildContext context, {
  required BatchSettleKind kind,
  required int count,
  required double total,
  List<FinancialAccount> accounts = const [],
  List<FinancialAccount> destinations = const [],
  String? initialAccountId,
  int savedDestinationCount = 0,
}) {
  return showModalBottomSheet<BatchSettleChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BatchSettleSheet(
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

class _BatchSettleSheet extends StatefulWidget {
  final BatchSettleKind kind;
  final int count;
  final double total;
  final List<FinancialAccount> accounts;
  final List<FinancialAccount> destinations;
  final String? initialAccountId;
  final int savedDestinationCount;

  const _BatchSettleSheet({
    required this.kind,
    required this.count,
    required this.total,
    required this.accounts,
    required this.destinations,
    required this.initialAccountId,
    required this.savedDestinationCount,
  });

  @override
  State<_BatchSettleSheet> createState() => _BatchSettleSheetState();
}

class _BatchSettleSheetState extends State<_BatchSettleSheet> {
  String? _accountId;
  String? _toAccountId;

  /// The destination question has been answered — an account, or an explicit
  /// "spend it". Separate from [_toAccountId] because null is a real answer.
  bool _destinationChosen = false;
  bool _useSavedDestinations = true;
  bool _alreadyInLedger = false;
  DateTime _date = DateTime.now();
  bool _submitting = false;

  bool get _isSetAside => widget.kind == BatchSettleKind.setAsides;
  bool get _isInstallments => widget.kind == BatchSettleKind.installments;

  /// Installments each carry their own account, so the sheet asks for none.
  bool get _needsAccount => !_isInstallments && !_alreadyInLedger;

  /// Bills and receivables can be flagged settled without writing the ledger
  /// (the user already logged them by hand). A set-aside is the transfer, and
  /// an installment payment IS its transaction, so neither offers the choice.
  bool get _offersLedgerOptOut =>
      widget.kind == BatchSettleKind.bills ||
      widget.kind == BatchSettleKind.receivables;

  /// Rows that don't name a destination of their own — the ones the shared
  /// destination applies to.
  int get _unnamedDestinations => _useSavedDestinations
      ? widget.count - widget.savedDestinationCount
      : widget.count;

  bool get _needsDestination => _isSetAside && _unnamedDestinations > 0;

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
          '${formatPeso(widget.total)} leaves the account you pick.',
        BatchSettleKind.receivables =>
          '${formatPeso(widget.total)} lands in the account you pick.',
        BatchSettleKind.setAsides =>
          '${formatPeso(widget.total)} moves out of the funding account. '
              'Setting money aside is a transfer, not spending.',
        BatchSettleKind.installments =>
          '${formatPeso(widget.total)} across this month\'s payments, each '
              'from its own account.',
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

  FinancialAccount? _accountById(List<FinancialAccount> list, String? id) {
    for (final a in list) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.accounts,
      selectedId: _accountId,
    );
    if (choice == null) return;
    setState(() {
      _accountId = choice.id;
      // A set-aside can't be transferred into the account it came from.
      if (_toAccountId != null && _toAccountId == _accountId) {
        _toAccountId = null;
      }
    });
  }

  Future<void> _pickDestination() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.destinations.where((a) => a.id != _accountId).toList(),
      selectedId: _destinationChosen ? _toAccountId : null,
      allowNone: true,
      noneLabel: 'Spend it (no transfer)',
    );
    if (choice == null) return;
    setState(() {
      _toAccountId = choice.id;
      _destinationChosen = true;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  bool get _canConfirm {
    if (_submitting) return false;
    if (_needsAccount && widget.accounts.isNotEmpty && _accountId == null) {
      return false;
    }
    if (_needsDestination && !_destinationChosen) return false;
    return true;
  }

  void _confirm() {
    if (!_canConfirm) return;
    setState(() => _submitting = true);
    Navigator.pop(
      context,
      BatchSettleChoice(
        accountId: _needsAccount ? _accountId : null,
        toAccountId: _toAccountId,
        useSavedDestinations: _useSavedDestinations,
        alreadyInLedger: _alreadyInLedger,
        date: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final destination = _accountById(widget.destinations, _toAccountId);
    // "Spend it" is a decision, not an empty field — say so once it's made.
    final destinationPlaceholder =
        _destinationChosen ? 'Spend it (no transfer)' : 'Choose where it goes';

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            SheetTitle(_title),
            const SizedBox(height: 6),
            Text(
              _subtitle,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            ),
            if (_offersLedgerOptOut) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _alreadyInLedger,
                onChanged: (v) => setState(() => _alreadyInLedger = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Already added to ledger'),
                subtitle: const Text(
                    "Just settle them — don't record transactions or touch "
                    'any balance.'),
              ),
            ],
            if (_needsAccount && widget.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              SheetFieldLabel(_accountLabel),
              SheetAccountField(
                account: _accountById(widget.accounts, _accountId),
                onTap: _pickAccount,
              ),
            ],
            if (_isSetAside) ...[
              if (widget.savedDestinationCount > 0) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _useSavedDestinations,
                  onChanged: (v) =>
                      setState(() => _useSavedDestinations = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${widget.savedDestinationCount} of ${widget.count} have '
                    'their own destination',
                  ),
                  subtitle: Text(
                    _useSavedDestinations
                        ? 'Each of those keeps it.'
                        : 'Send everything to one destination instead.',
                  ),
                ),
              ],
              if (_needsDestination) ...[
                const SizedBox(height: 12),
                SheetFieldLabel(
                  widget.savedDestinationCount > 0 && _useSavedDestinations
                      ? 'Set the other $_unnamedDestinations aside into'
                      : 'Set aside into',
                ),
                SheetAccountField(
                  account: destination,
                  placeholder: destinationPlaceholder,
                  onTap: _pickDestination,
                ),
              ],
            ],
            const SizedBox(height: 12),
            const SheetFieldLabel('Date'),
            SheetPickerBox(
              onTap: _pickDate,
              trailingIcon: Icons.calendar_today_outlined,
              child: Text(
                DateFormat('MMMM d, yyyy').format(_date),
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: _confirmLabel,
              onPressed: _canConfirm ? _confirm : null,
              isLoading: _submitting,
            ),
          ],
        ),
      ),
    );
  }
}
