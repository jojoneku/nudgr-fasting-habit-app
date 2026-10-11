import 'package:flutter/material.dart';

import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';
import 'web_budget_shared.dart';

/// The v2 "Budget groups" dialog (Forms canvas): one row per group with its
/// colour dot, name and category count, Rename and Delete at the right, a
/// dashed "Add a group…" field that commits on Enter, the helper line, and
/// Done. Same presenter calls as the pre-v2 `showWebManageGroupsDialog`
/// ([BudgetPresenter.addGroup], [BudgetPresenter.renameGroup],
/// [BudgetPresenter.deleteGroup]); only the chrome changed.
Future<void> showWebManageGroupsDialogV2(
  BuildContext context, {
  required BudgetPresenter presenter,
}) {
  return showWebDialog<void>(
    context,
    builder: (_) => _WebManageGroupsDialogV2(presenter: presenter),
  );
}

class _WebManageGroupsDialogV2 extends StatefulWidget {
  final BudgetPresenter presenter;

  const _WebManageGroupsDialogV2({required this.presenter});

  @override
  State<_WebManageGroupsDialogV2> createState() =>
      _WebManageGroupsDialogV2State();
}

class _WebManageGroupsDialogV2State extends State<_WebManageGroupsDialogV2> {
  final _addCtrl = TextEditingController();
  final _addFocus = FocusNode();
  bool _hasDraft = false;

  BudgetPresenter get presenter => widget.presenter;

  @override
  void dispose() {
    _addCtrl.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  /// Rows this group holds this month — expense categories for an expense
  /// group, savings targets for a savings one.
  int _countFor(BudgetGroupDef g) => g.isSavings
      ? presenter.savingsBudgets.where((e) => e.budget.group == g.id).length
      : presenter.categoriesByGroup[g.id]?.length ?? 0;

  /// Where the presenter moves a deleted group's rows: its first remaining
  /// expense group. Named in the helper and the confirm so the dialog tells
  /// the truth about what Delete does.
  BudgetGroupDef? _fallbackFor(BudgetGroupDef? deleting) =>
      presenter.expenseGroups.where((g) => g.id != deleting?.id).firstOrNull;

  Future<void> _add() async {
    final name = _addCtrl.text.trim();
    // A blank name is rejected silently; the field just keeps focus.
    if (name.isEmpty) return;
    _addCtrl.clear();
    setState(() => _hasDraft = false);
    await presenter.addGroup(name);
    if (mounted) _addFocus.requestFocus();
  }

  Future<void> _rename(BudgetGroupDef g) async {
    final name = await _promptName(context, initial: g.name);
    if (name != null && name != g.name) await presenter.renameGroup(g.id, name);
  }

  Future<void> _delete(BudgetGroupDef g) async {
    final fallback = _fallbackFor(g);
    final where = fallback == null ? 'the first group' : '"${fallback.name}"';
    final confirmed = await showWebConfirm(
      context,
      title: 'Delete group?',
      message: 'Categories in "${g.name}" move to $where. '
          'Nothing is removed from the budget.',
    );
    if (confirmed) await presenter.deleteGroup(g.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;

    return WebDialog(
      title: 'Budget groups',
      subtitle: 'Groups order the table and drive the allocation donut.',
      primaryExpands: false,
      body: ListenableBuilder(
        listenable: presenter,
        builder: (context, _) {
          final groups = presenter.groups;
          final fallback = _fallbackFor(null);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < groups.length; i++)
                _GroupRow(
                  key: WebKeys.budgetGroupRow(groups[i].id),
                  group: groups[i],
                  color: webBudgetGroupColor(context, i),
                  count: _countFor(groups[i]),
                  onRename: () => _rename(groups[i]),
                  // Built-in groups come back from the defaults on reload,
                  // so deleting one would only look like it worked.
                  onDelete:
                      groups[i].isBuiltIn ? null : () => _delete(groups[i]),
                  divider: i < groups.length - 1,
                ),
              const SizedBox(height: WebInsets.md),
              _AddGroupField(
                controller: _addCtrl,
                focusNode: _addFocus,
                hasDraft: _hasDraft,
                onChanged: (v) =>
                    setState(() => _hasDraft = v.trim().isNotEmpty),
                onSubmit: _add,
              ),
              const SizedBox(height: WebInsets.sm),
              Text(
                fallback == null
                    ? 'Deleting a group keeps every category in the budget.'
                    : 'Deleting a group moves its categories to '
                        '"${fallback.name}". Nothing is removed from the budget.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          );
        },
      ),
      primary: FilledButton(
        key: WebKeys.budgetGroupsClose,
        onPressed: () => Navigator.of(context).pop(),
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
        child: const Text('Done'),
      ),
    );
  }
}

/// The rename prompt on the kit: one field, Enter or Save commits, Cancel,
/// × and Esc dismiss. Resolves to the trimmed name or null.
Future<String?> _promptName(BuildContext context, {required String initial}) {
  return showWebDialog<String>(
    context,
    builder: (_) => _RenamePrompt(initial: initial),
  );
}

/// Owns its controller in State so it outlives the dialog's exit transition
/// (disposing on pop completion raced the field's last build).
class _RenamePrompt extends StatefulWidget {
  final String initial;

  const _RenamePrompt({required this.initial});

  @override
  State<_RenamePrompt> createState() => _RenamePromptState();
}

class _RenamePromptState extends State<_RenamePrompt> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _ctrl.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return WebDialog(
      title: 'Rename group',
      width: 420,
      onSubmit: _save,
      primaryExpands: false,
      body: WebField(
        label: 'Group name',
        child: WebInput(
          key: WebKeys.budgetGroupsRenameField,
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
        ),
      ),
      secondary: TextButton(
        key: WebKeys.budgetGroupsRenameCancel,
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton(
        key: WebKeys.budgetGroupsRenameSave,
        onPressed: _save,
        child: const Text('Save'),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final BudgetGroupDef group;
  final Color color;
  final int count;
  final VoidCallback onRename;
  final VoidCallback? onDelete;
  final bool divider;

  const _GroupRow({
    super.key,
    required this.group,
    required this.color,
    required this.count,
    required this.onRename,
    required this.onDelete,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;
    final role = group.isSavings
        ? 'Savings group'
        : group.isBuiltIn
            ? 'Built-in'
            : null;

    return Container(
      constraints: const BoxConstraints(minHeight: kWebHitTarget),
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xs),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: cs.outlineVariant))
            : null,
      ),
      child: Row(
        children: [
          WebDot(color: color),
          const SizedBox(width: WebInsets.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: group.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
                children: [
                  TextSpan(
                    text: ' · $count ${count == 1 ? 'category' : 'categories'}'
                        '${role == null ? '' : ' · $role'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            key: WebKeys.budgetGroupsRename,
            onPressed: onRename,
            style: TextButton.styleFrom(
              minimumSize: const Size(kWebHitTarget, kWebHitTarget),
              foregroundColor: cs.onSurface,
            ),
            child: const Text('Rename'),
          ),
          if (onDelete != null)
            TextButton(
              key: WebKeys.budgetGroupsDelete,
              onPressed: onDelete,
              style: TextButton.styleFrom(
                minimumSize: const Size(kWebHitTarget, kWebHitTarget),
                foregroundColor: cs.error,
              ),
              child: const Text('Delete'),
            ),
        ],
      ),
    );
  }
}

/// The dashed "＋ Add a group…" field. Enter adds; a filled Add button shows
/// once there is text, for pointer users.
class _AddGroupField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasDraft;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  const _AddGroupField({
    required this.controller,
    required this.focusNode,
    required this.hasDraft,
    required this.onChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;
    return SizedBox(
      height: kWebInputHeight,
      child: TextField(
        key: WebKeys.budgetGroupsAdd,
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmit(),
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13.5),
        decoration: InputDecoration(
          hintText: '＋ Add a group…',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: muted,
            fontSize: 13.5,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: WebInsets.md,
            vertical: WebInsets.md,
          ),
          filled: true,
          fillColor: Colors.transparent,
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.mdBorder,
            borderSide: BorderSide(color: cs.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadii.mdBorder,
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
          suffixIcon: hasDraft
              ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FilledButton(
                    onPressed: onSubmit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(56, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Add'),
                  ),
                )
              : null,
          suffixIconConstraints:
              const BoxConstraints(minHeight: 36, minWidth: 60),
        ),
      ),
    );
  }
}
