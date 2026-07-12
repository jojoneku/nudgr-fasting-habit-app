import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Fund a goal / savings / sinking-fund pocket — a plain transfer from a liquid
/// account into the pocket. Opened from the goal card's "Fund" action. Handles
/// sub-account pockets (the destination is fixed to [goal], so it isn't subject
/// to the generic transfer picker's sub-account exclusion).
class FundGoalSheet extends StatefulWidget {
  const FundGoalSheet({
    super.key,
    required this.presenter,
    required this.goal,
  });

  final TreasuryDashboardPresenter presenter;
  final FinancialAccount goal;

  @override
  State<FundGoalSheet> createState() => _FundGoalSheetState();
}

class _FundGoalSheetState extends State<FundGoalSheet> {
  late final TextEditingController _amountCtrl;
  String? _fromId;
  bool _saving = false;

  List<FinancialAccount> get _sources => widget.presenter.liquidAccounts;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    // If the goal has a target, prefill the remaining-to-goal as a convenience.
    final target = widget.goal.goalTarget;
    if (target != null && target > widget.goal.balance) {
      _amountCtrl.text = (target - widget.goal.balance).toStringAsFixed(2);
    }
    _fromId = _sources.isNotEmpty ? _sources.first.id : null;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount =
        double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0 || _fromId == null || _saving) return;
    setState(() => _saving = true);
    await widget.presenter.fundGoal(
      fromAccountId: _fromId!,
      toAccountId: widget.goal.id,
      amount: amount,
      description: 'Fund ${widget.goal.name}',
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(
      context,
      '${widget.goal.name} funded · ${formatPeso(amount)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_sources.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          'Add a bank, e-wallet, or cash account first — funding moves money '
          'from one of those into this pocket.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final target = widget.goal.goalTarget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          target != null
              ? 'Now ${formatPeso(widget.goal.balance)} of ${formatPeso(target)}'
              : 'Balance ${formatPeso(widget.goal.balance)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _amountCtrl,
          enabled: !_saving,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: '₱ ',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _fromId,
          decoration: const InputDecoration(labelText: 'Fund from'),
          items: _sources
              .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
              .toList(),
          onChanged: _saving ? null : (v) => setState(() => _fromId = v),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Fund ${widget.goal.name}'),
        ),
      ],
    );
  }
}
