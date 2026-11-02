import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/captured_transaction.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/capture_inbox_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_chips.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import 'capture_edit_sheet.dart';

/// One pending capture: source and time, amount and direction, the two
/// chips the user may still have to fill, then Decline / Approve.
///
/// All state and decisions live in [CaptureInboxPresenter]; this widget only
/// renders what it is given and forwards taps. Theme colors only.
class CaptureRow extends StatelessWidget {
  final CaptureInboxPresenter presenter;
  final CapturedTransaction item;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  const CaptureRow({
    super.key,
    required this.presenter,
    required this.item,
    required this.onApprove,
    required this.onDecline,
  });

  static final _timeFmt = _TimeFmt();

  Color _typeColor(ColorScheme cs, TransactionType? t) => switch (t) {
        TransactionType.inflow => cs.tertiary,
        TransactionType.outflow => cs.error,
        TransactionType.transfer => cs.primary,
        null => cs.onSurfaceVariant,
      };

  IconData _typeIcon(TransactionType? t) => switch (t) {
        TransactionType.inflow => Icons.arrow_downward_rounded,
        TransactionType.outflow => Icons.arrow_upward_rounded,
        TransactionType.transfer => Icons.swap_horiz_rounded,
        null => Icons.help_outline_rounded,
      };

  String _amountText(double? amount, TransactionType? t) {
    if (amount == null) return '—';
    final f = formatPeso(amount);
    return switch (t) {
      TransactionType.inflow => '+$f',
      TransactionType.outflow => '−$f',
      _ => f,
    };
  }

  Future<void> _pickAccount(BuildContext context,
      {required bool destination}) async {
    final choice = await showAccountPicker(
      context,
      accounts: presenter.accounts,
      selectedId:
          destination ? item.draft.transferToAccountId : item.draft.accountId,
    );
    if (choice == null || choice.id == null) return;
    final draft = destination
        ? item.draft.copyWith(transferToAccountId: choice.id)
        : item.draft.copyWith(accountId: choice.id);
    await presenter.setDraft(item.id, draft);
    if (destination) return;
    // Remember the choice so the next capture from this card / app lands
    // on the right account without asking.
    final last4 = item.accountLast4;
    if (last4 != null) {
      await presenter.setLast4Account(last4, choice.id);
    } else if (presenter.settings.accountBySource[item.sourceApp] == null) {
      await presenter.setSourceAccount(item.sourceApp, choice.id);
    }
  }

  Future<void> _pickCategory(BuildContext context) async {
    final want = item.draft.type == TransactionType.inflow
        ? CategoryType.income
        : CategoryType.expense;
    final choice = await showCategoryPicker(
      context,
      categories: presenter.categories.where((c) => c.type == want).toList(),
      selectedId: item.draft.categoryId,
      allowNone: false,
    );
    if (choice == null || choice.id == null) return;
    await presenter.setDraft(
        item.id, item.draft.copyWith(categoryId: choice.id));
  }

  Future<void> _pickType(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<TransactionType>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const SheetTitle('What kind of movement?'),
            for (final (t, label, icon) in [
              (
                TransactionType.outflow,
                'Money out',
                Icons.arrow_upward_rounded
              ),
              (
                TransactionType.inflow,
                'Money in',
                Icons.arrow_downward_rounded
              ),
              (
                TransactionType.transfer,
                'Transfer between my accounts',
                Icons.swap_horiz_rounded
              ),
            ])
              ListTile(
                leading: Icon(icon, color: _typeColor(cs, t)),
                title: Text(label),
                onTap: () => Navigator.of(ctx).pop(t),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (picked == null) return;
    var draft = item.draft.copyWith(type: picked);
    if (picked == TransactionType.transfer) {
      draft = draft.copyWith(categoryId: FinanceCategory.transferCategoryId);
    } else if (draft.categoryId == FinanceCategory.transferCategoryId) {
      draft = _withoutCategory(draft);
    }
    await presenter.setDraft(item.id, draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = item.draft;
    final color = _typeColor(cs, d.type);
    final missing = item.missing;
    final ready = item.isReady;
    final account = presenter.accountById(d.accountId);
    final toAccount = presenter.accountById(d.transferToAccountId);
    final category = presenter.categoryById(d.categoryId);
    final isTransfer = d.type == TransactionType.transfer;
    final twin = presenter.twinOf(item);
    final duplicate = twin == null && presenter.isPossibleDuplicate(item);
    final lowConfidence = item.confidence > 0 && item.confidence < 0.6;

    String? blocker;
    if (!ready) {
      final first = missing.first;
      blocker = 'Needs ${first.label.toLowerCase()}';
    }

    return Semantics(
      label:
          '${item.sourceLabel} capture, ${_amountText(d.amount, d.type)}, ${d.description}',
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm + 4, AppSpacing.md, AppSpacing.sm),
        onTap: () =>
            showCaptureEditSheet(context, presenter: presenter, item: item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source · time ........................ badges
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.sourceLabel} · ${_timeFmt.format(item.capturedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                if (twin != null) ...[
                  const SizedBox(width: 6),
                  AppBadge(
                      text: 'Same as ${twin.sourceLabel}', color: cs.secondary),
                ] else if (duplicate) ...[
                  const SizedBox(width: 6),
                  AppBadge(text: 'Possible duplicate', color: cs.secondary),
                ],
                if (lowConfidence && !duplicate && twin == null) ...[
                  const SizedBox(width: 6),
                  AppBadge(text: 'Check this', color: cs.tertiary),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Direction glyph + description ........ amount
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppIconBadge(
                  icon: _typeIcon(d.type),
                  color: color,
                  size: 36,
                  iconSize: 18,
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Text(
                    d.description.isNotEmpty ? d.description : 'No description',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _amountText(d.amount, d.type),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: d.amount == null ? cs.onSurfaceVariant : color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Chips: the structured fields, each a one-tap picker.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (d.type == null)
                  _Chip(
                    icon: Icons.help_outline_rounded,
                    label: 'Pick type',
                    placeholder: true,
                    onTap: () => _pickType(context),
                  ),
                _Chip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: account?.name ??
                      (isTransfer ? 'From account' : 'Pick account'),
                  placeholder: account == null,
                  onTap: () => _pickAccount(context, destination: false),
                ),
                if (isTransfer)
                  _Chip(
                    icon: Icons.east_rounded,
                    label: toAccount?.name ?? 'To account',
                    placeholder: toAccount == null,
                    onTap: () => _pickAccount(context, destination: true),
                  )
                else if (d.type != null)
                  _Chip(
                    icon: Icons.sell_outlined,
                    label: category?.name ?? 'Pick category',
                    placeholder: category == null,
                    onTap: () => _pickCategory(context),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Decline / Approve, bottom-right, each ≥ 44 px tall.
            Row(
              children: [
                if (blocker != null)
                  Expanded(
                    child: Text(
                      blocker,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: cs.tertiary),
                    ),
                  )
                else
                  const Spacer(),
                TextButton(
                  onPressed: onDecline,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(72, 44),
                    foregroundColor: cs.onSurfaceVariant,
                  ),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  onPressed: ready ? onApprove : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(104, 44),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A 36 px pill with a 44 px hit area. [placeholder] renders the unfilled
/// state in the tertiary color so an empty field reads as a prompt.
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool placeholder;
  final VoidCallback onTap;

  const _Chip({
    required this.icon,
    required this.label,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = placeholder ? cs.tertiary : cs.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: placeholder
                  ? cs.tertiaryContainer.withValues(alpha: 0.35)
                  : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: placeholder ? cs.tertiary : cs.outlineVariant,
                width: placeholder ? 1.2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeFmt {
  String format(DateTime t) {
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }
}

/// `copyWith` cannot null a field; the type picker needs to drop the reserved
/// transfer category when the row stops being a transfer.
ParsedTransaction _withoutCategory(ParsedTransaction d) => ParsedTransaction(
      amount: d.amount,
      type: d.type,
      accountId: d.accountId,
      description: d.description,
      descriptionIsClean: d.descriptionIsClean,
      date: d.date,
      note: d.note,
    );
