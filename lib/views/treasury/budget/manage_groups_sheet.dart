import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class ManageGroupsSheet extends StatefulWidget {
  final BudgetPresenter presenter;

  const ManageGroupsSheet({super.key, required this.presenter});

  @override
  State<ManageGroupsSheet> createState() => _ManageGroupsSheetState();
}

class _ManageGroupsSheetState extends State<ManageGroupsSheet> {
  void _showAddDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Group name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await widget.presenter.addGroup(name);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BudgetGroupDef group) {
    final ctrl = TextEditingController(text: group.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await widget.presenter.renameGroup(group.id, name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BudgetGroupDef group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group?'),
        content: Text(
          'Budgets in "${group.name}" will move to the first available group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.presenter.deleteGroup(group.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final groups = widget.presenter.groups;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: groups.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
              itemBuilder: (context, i) {
                final g = groups[i];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(g.name, style: theme.textTheme.bodyMedium),
                  // Role descriptor derived from the group's flags — not a
                  // hardcoded name, so a renamed savings group still reads right.
                  subtitle: g.isSavings
                      ? Text('Savings group',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant))
                      : g.isBuiltIn
                          ? Text('Built-in',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant))
                          : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'Rename',
                        onPressed: () => _showRenameDialog(g),
                      ),
                      if (!g.isBuiltIn)
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: cs.error),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(g),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppPrimaryButton(
                label: 'Add Group',
                onPressed: _showAddDialog,
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
