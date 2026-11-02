import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/captured_transaction.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/capture_inbox_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_chips.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Full edit of one inbox row's draft. Saving only updates the draft — the
/// row stays pending until the user taps Approve, so the one commit path
/// stays in the presenter.
Future<void> showCaptureEditSheet(
  BuildContext context, {
  required CaptureInboxPresenter presenter,
  required CapturedTransaction item,
}) async {
  final edited = await AppBottomSheet.show<ParsedTransaction>(
    context: context,
    title: 'Edit capture',
    body: _EditBody(presenter: presenter, item: item),
  );
  if (edited != null) await presenter.setDraft(item.id, edited);
}

class _EditBody extends StatefulWidget {
  final CaptureInboxPresenter presenter;
  final CapturedTransaction item;
  const _EditBody({required this.presenter, required this.item});

  @override
  State<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends State<_EditBody> {
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late TransactionType _type;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  bool _showRaw = false;

  @override
  void initState() {
    super.initState();
    final d = widget.item.draft;
    _amount = TextEditingController(
        text: d.amount == null ? '' : d.amount!.toStringAsFixed(2));
    _description = TextEditingController(text: d.description);
    _type = d.type ?? TransactionType.outflow;
    _accountId = d.accountId;
    _toAccountId = d.transferToAccountId;
    _categoryId = d.categoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _categoriesForType => widget.presenter.categories
      .where((c) =>
          c.type ==
          (_type == TransactionType.inflow
              ? CategoryType.income
              : CategoryType.expense))
      .toList();

  Future<void> _pickAccount({required bool destination}) async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.presenter.accounts,
      selectedId: destination ? _toAccountId : _accountId,
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (destination) {
        _toAccountId = choice.id;
      } else {
        _accountId = choice.id;
      }
    });
  }

  void _save() {
    final amount = evalAmountExpression(_amount.text);
    if (amount == null || amount <= 0) {
      AppToast.error(context, 'Enter an amount greater than 0');
      return;
    }
    final isTransfer = _type == TransactionType.transfer;
    Navigator.of(context).pop(ParsedTransaction(
      amount: amount,
      type: _type,
      accountId: _accountId,
      transferToAccountId: isTransfer ? _toAccountId : null,
      categoryId: isTransfer ? FinanceCategory.transferCategoryId : _categoryId,
      description: _description.text.trim(),
      descriptionIsClean: true,
      date: widget.item.draft.date ?? widget.item.capturedAt,
      note: widget.item.draft.note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = widget.presenter;
    final isTransfer = _type == TransactionType.transfer;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetLabeledField(
            label: 'Amount',
            child: TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [CalcAmountInputFormatter()],
              decoration: const InputDecoration(prefixText: '₱ '),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SheetLabeledField(
            label: 'Type',
            child: SheetSegmentedToggle<TransactionType>(
              segments: [
                SheetSegment(
                    label: 'Out',
                    value: TransactionType.outflow,
                    accent: cs.error),
                SheetSegment(
                    label: 'In',
                    value: TransactionType.inflow,
                    accent: cs.tertiary),
                SheetSegment(
                    label: 'Transfer',
                    value: TransactionType.transfer,
                    accent: cs.primary),
              ],
              value: _type,
              onChanged: (t) => setState(() {
                _type = t;
                // A category of the other kind would be silently wrong.
                if (_categoryId != null &&
                    !_categoriesForType.any((c) => c.id == _categoryId)) {
                  _categoryId = null;
                }
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SheetLabeledField(
            label: isTransfer ? 'From account' : 'Account',
            child: SheetAccountField(
              account: p.accountById(_accountId),
              onTap: () => _pickAccount(destination: false),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isTransfer)
            SheetLabeledField(
              label: 'To account',
              child: SheetAccountField(
                account: p.accountById(_toAccountId),
                placeholder: 'Select destination',
                onTap: () => _pickAccount(destination: true),
              ),
            )
          else
            SheetLabeledField(
              label: 'Category',
              child: CategoryPickerField(
                categories: _categoriesForType,
                selectedId: _categoryId,
                onChanged: (id) => setState(() => _categoryId = id),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SheetLabeledField(
            label: 'Description',
            child: TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What was this for?'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            icon: Icon(_showRaw ? Icons.expand_less : Icons.expand_more,
                size: 18),
            label: Text(_showRaw ? 'Hide what we read' : 'Show what we read'),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: cs.onSurfaceVariant,
            ),
          ),
          if (_showRaw)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm + 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                [
                  if (widget.item.rawTitle.trim().isNotEmpty)
                    widget.item.rawTitle.trim(),
                  widget.item.rawText.trim(),
                ].join('\n'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          AppPrimaryButton(label: 'Save draft', onPressed: _save),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
