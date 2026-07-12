import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/finance/bill.dart';
import '../../../models/finance/finance_parse_result.dart';
import '../../../presenters/bills_receivables_presenter.dart';
import '../../../presenters/ledger_presenter.dart';
import '../../../presenters/treasury_dashboard_presenter.dart';
import '../../treasury/ledger/add_transaction_sheet.dart';
import '../finance/ledger_chat_panel.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import '../../../utils/finance_format.dart';
import 'hub_card_header.dart';

class TreasuryHubCard extends StatelessWidget {
  const TreasuryHubCard({
    super.key,
    required this.treasury,
    required this.onNavigate,
    this.ledger,
    this.bills,
  });

  final TreasuryDashboardPresenter treasury;
  final VoidCallback onNavigate;

  /// When provided, a compact chat bar is shown so an expense can be logged
  /// straight from the hub without opening the full Treasury module. The chat
  /// pipeline (parse → clarify → confirm) is the same one the Ledger uses; this
  /// is just a second, condensed entry point onto it.
  final LedgerPresenter? ledger;

  /// When provided, upcoming bills expose a Pay action (gated behind a confirm
  /// sheet — never a silent money mutation).
  final BillsReceivablesPresenter? bills;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: treasury,
      builder: (context, _) {
        final isActive = treasury.hasBillImminent;
        // The header + overview navigate into the module; the bill list (with
        // Pay actions) and the chat bar below must NOT, so we wrap only the top
        // region in the tap target instead of the whole AppCard.
        return AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPressable(
                onTap: onNavigate,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HubCardHeader(
                      icon: isActive
                          ? Icons.account_balance
                          : Icons.account_balance_outlined,
                      title: 'Finance',
                      accentColor: context.appColors.gold,
                      isActive: isActive,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _FinanceHero(treasury: treasury),
                    const SizedBox(height: AppSpacing.md),
                    _CashflowBars(treasury: treasury),
                  ],
                ),
              ),
              if (treasury.upcomingBills.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _UpcomingBills(treasury: treasury, bills: bills),
              ],
              if (ledger != null) ...[
                const SizedBox(height: AppSpacing.md),
                _QuickLogChat(ledger: ledger!),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Hero metric: the forecasted ending cash balance (liquid − set-asides −
/// bills − remaining budget), with a net-worth variant in the last days of the
/// month. A savings-rate chip sits alongside.
class _FinanceHero extends StatelessWidget {
  const _FinanceHero({required this.treasury});
  final TreasuryDashboardPresenter treasury;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;

    final now = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    final monthEnd = now.day >= daysInMonth - 2;

    final value = monthEnd ? treasury.netWorth : treasury.forecastedNetBalance;
    final label = monthEnd ? 'NET WORTH' : 'FORECASTED ENDING BALANCE';
    final sr = treasury.savingsRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                formatPeso(value),
                style: AppTextStyles.numeric(
                        fontSize: 24, weight: FontWeight.w800)
                    .copyWith(
                        color: value >= 0 ? c.fast : theme.colorScheme.error),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (sr != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.move.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${formatPercent(sr)} saved',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: c.move, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// In/out cashflow for the month as two proportional bars.
class _CashflowBars extends StatelessWidget {
  const _CashflowBars({required this.treasury});
  final TreasuryDashboardPresenter treasury;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inflow = treasury.monthTotalInflow;
    final outflow = treasury.monthTotalOutflow;
    final max = [inflow, outflow, 1.0].reduce((a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppLinearProgress(
            value: inflow / max,
            label: 'In',
            valueText: formatPesoCompact(inflow),
            color: context.appColors.move,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppLinearProgress(
            value: outflow / max,
            label: 'Out',
            valueText: formatPesoCompact(outflow),
            color: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }
}

/// Upcoming unpaid bills for the month with a day countdown + Pay action. Sits
/// outside the navigation tap target so per-bill actions don't push a screen.
class _UpcomingBills extends StatelessWidget {
  const _UpcomingBills({required this.treasury, this.bills});
  final TreasuryDashboardPresenter treasury;
  final BillsReceivablesPresenter? bills;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = treasury.upcomingBills.take(3).toList();
    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMING UP',
          style: AppTextStyles.labelSmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final bill in upcoming)
          _BillRow(
            bill: bill,
            overdue: treasury.isBillOverdue(bill),
            onPay: bills == null
                ? null
                : () => _showPayBillSheet(context, bills!, bill),
          ),
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill, required this.overdue, this.onPay});
  final Bill bill;
  final bool overdue;
  final VoidCallback? onPay;

  /// Human day-count from today to the bill's day-of-month.
  static String _dueLabel(int dueDay, bool overdue) {
    if (overdue) return 'Overdue';
    final today = DateTime.now().day;
    final diff = dueDay - today;
    if (diff <= 0) return 'Due today';
    if (diff == 1) return 'Tomorrow';
    return 'in ${diff}d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imminent = overdue || (bill.dueDay - DateTime.now().day) <= 1;
    final dot = imminent ? theme.colorScheme.error : context.appColors.bills;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(bill.name, style: AppTextStyles.bodySmall)),
          Text(
            _dueLabel(bill.dueDay, overdue),
            style: AppTextStyles.labelSmall.copyWith(
              color: imminent
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            formatPeso(bill.amount),
            style:
                AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700),
          ),
          if (onPay != null) ...[
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              height: 32,
              child: TextButton(
                onPressed: onPay,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  foregroundColor: context.appColors.gold,
                ),
                child: const Text('Pay'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Confirm sheet for paying a bill: shows the amount (editable) and a
/// source-account selector preselected to the bill's usual account. Nothing is
/// committed until the user confirms.
Future<void> _showPayBillSheet(
  BuildContext context,
  BillsReceivablesPresenter bills,
  Bill bill,
) {
  return AppBottomSheet.show<void>(
    context: context,
    title: 'Pay ${bill.name}',
    body: _PayBillSheet(bills: bills, bill: bill),
  );
}

class _PayBillSheet extends StatefulWidget {
  const _PayBillSheet({required this.bills, required this.bill});
  final BillsReceivablesPresenter bills;
  final Bill bill;

  @override
  State<_PayBillSheet> createState() => _PayBillSheetState();
}

class _PayBillSheetState extends State<_PayBillSheet> {
  late final TextEditingController _amountCtrl;
  String? _accountId;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.bill.amount.toStringAsFixed(2),
    );
    final accounts = widget.bills.accounts;
    // Preselect the bill's usual funding account; fall back to the first.
    _accountId = widget.bill.accountId ??
        (accounts.isNotEmpty ? accounts.first.id : null);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount =
        double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0 || _accountId == null || _paying) return;
    setState(() => _paying = true);
    await widget.bills.markBillPaid(
      widget.bill.id,
      paidAmount: amount,
      accountId: _accountId,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(
        context, '${widget.bill.name} paid · ${formatPeso(amount)}');
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.bills.accounts;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _amountCtrl,
          enabled: !_paying,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: AppTextStyles.bodyMedium,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: '₱ ',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _accountId,
          decoration: const InputDecoration(labelText: 'Pay from'),
          items: accounts
              .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
              .toList(),
          onChanged: _paying ? null : (v) => setState(() => _accountId = v),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _paying || _accountId == null ? null : _confirm,
          child: _paying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Confirm payment · ${formatPeso(widget.bill.amount)}'),
        ),
      ],
    );
  }
}

// ── Quick-log chat ────────────────────────────────────────────────────────────
//
// A condensed view onto [LedgerPresenter]'s chat pipeline, embedded in the hub
// card. Sending runs the same parse → clarify → confirm loop as the Ledger;
// because it's the same presenter instance, an unfinished conversation started
// here is picked up seamlessly if the user then opens the full module.

class _QuickLogChat extends StatefulWidget {
  const _QuickLogChat({required this.ledger});

  final LedgerPresenter ledger;

  @override
  State<_QuickLogChat> createState() => _QuickLogChatState();
}

class _QuickLogChatState extends State<_QuickLogChat> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  String? _lastToastSummary;

  LedgerPresenter get ledger => widget.ledger;

  @override
  void initState() {
    super.initState();
    ledger.addListener(_onLedgerChange);
  }

  @override
  void dispose() {
    ledger.removeListener(_onLedgerChange);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Mirrors the side effects the Ledger view runs on presenter changes:
  /// surface the post-commit toast, and when the AI can't auto-resolve (or AI
  /// is unavailable) open the prefilled form sheet. Both are guarded on route
  /// currency so they don't double up with the Ledger view when the full module
  /// is open on top of the hub.
  void _onLedgerChange() {
    if (!mounted) return;
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrent) return;

    final summary = ledger.lastCommittedSummary;
    if (summary != null && summary != _lastToastSummary) {
      _lastToastSummary = summary;
      AppToast.success(context, summary);
      ledger.clearLastCommittedSummary();
    }

    final prefill = ledger.pendingFormPrefill;
    if (prefill != null) {
      ledger.consumeFormPrefill();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFormSheet(prefill);
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      _ctrl.clear();
      await ledger.sendChatInput(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openFormSheet(ParsedTransaction prefill) {
    AppBottomSheet.show(
      context: context,
      title: 'Log Transaction',
      body: AddTransactionSheet(
        presenter: ledger,
        prefill: prefill,
        initialDate: ledger.selectedDate,
      ),
    );
  }

  String _hint(LedgerPresenter p) {
    if (!p.isSelectedDateToday) return 'Open Finance to log on that day';
    if (p.chatState.phase == ChatPhase.clarifying) return 'Reply…';
    return 'Log an expense…';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final state = ledger.chatState;
        // Quick logging stamps "today", so it's gated to the current day; the
        // full form (reachable via the card header) handles back-dated entries.
        final canSend = ledger.isSelectedDateToday;
        final classifying = state.phase == ChatPhase.classifying;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LedgerChatPanel(ledger: ledger),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    enabled: canSend && !classifying,
                    style: AppTextStyles.bodyMedium,
                    decoration: InputDecoration(
                      hintText: _hint(ledger),
                      hintStyle: AppTextStyles.bodyMedium.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    icon: _sending || classifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: canSend && !classifying ? _send : null,
                    tooltip: 'Send',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
