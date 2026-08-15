import 'package:flutter/material.dart';

import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import '../../widgets/web_widgets.dart';

/// Desktop counterpart of the mobile `ManageGroupsSheet`.
///
/// Web could assign a budget to an existing group but never create, rename or
/// delete one — so the Allocation by Group card was unpopulatable from the
/// desktop, and a web-only user had to pick up their phone to add a group.
Future<void> showWebManageGroupsDialog(
  BuildContext context, {
  required BudgetPresenter presenter,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _WebManageGroupsDialog(presenter: presenter),
  );
}

class _WebManageGroupsDialog extends StatelessWidget {
  final BudgetPresenter presenter;

  const _WebManageGroupsDialog({required this.presenter});

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String initial = '',
  }) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Group name'),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) Navigator.pop(ctx, name);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final name =
        await _promptName(context, title: 'New group', confirmLabel: 'Add');
    if (name != null) await presenter.addGroup(name);
  }

  Future<void> _rename(BuildContext context, BudgetGroupDef g) async {
    final name = await _promptName(context,
        title: 'Rename group', confirmLabel: 'Save', initial: g.name);
    if (name != null) await presenter.renameGroup(g.id, name);
  }

  Future<void> _delete(BuildContext context, BudgetGroupDef g) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
          'Budgets in "${g.name}" will move to the first available group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await presenter.deleteGroup(g.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      title: const Text('Budget groups'),
      content: SizedBox(
        width: 460,
        child: ListenableBuilder(
          listenable: presenter,
          builder: (context, _) {
            final groups = presenter.groups;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                    itemBuilder: (context, i) {
                      final g = groups[i];
                      // Role descriptor from the group's flags, not its name,
                      // so a renamed savings group still reads right.
                      final subtitle = g.isSavings
                          ? 'Savings group'
                          : g.isBuiltIn
                              ? 'Built-in'
                              : null;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(g.name, style: theme.textTheme.bodyMedium),
                        subtitle: subtitle == null
                            ? null
                            : Text(subtitle,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Rename',
                              onPressed: () => _rename(context, g),
                            ),
                            if (!g.isBuiltIn)
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 18, color: cs.error),
                                tooltip: 'Delete',
                                onPressed: () => _delete(context, g),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: WebInsets.lg),
                OutlinedButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add group'),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
