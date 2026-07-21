import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/local_storage_service.dart';
import '../../services/snapshot_service.dart';
import '../../utils/app_spacing.dart';
import '../widgets/system/system.dart';

/// Restore-from-snapshot UI (Plan 053 Phase 3.5). Lists the user's immutable
/// cloud snapshots newest-first and lets them roll the device back to one.
///
/// The restore is a raw local write (no dirty mark / no LWW bump), then we fire
/// `storage.onRemoteDataApplied` so every presenter reloads — and the next pull
/// still lets a newer cloud row win, so this can't fight live sync.
Future<void> showRestoreBackupSheet(
  BuildContext context, {
  required LocalStorageService storage,
  required String userId,
}) {
  final service = SnapshotService(
    supabase: Supabase.instance.client,
    storage: storage,
    userId: userId,
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RestoreBackupSheet(service: service, storage: storage),
  );
}

class _RestoreBackupSheet extends StatefulWidget {
  final SnapshotService service;
  final LocalStorageService storage;

  const _RestoreBackupSheet({required this.service, required this.storage});

  @override
  State<_RestoreBackupSheet> createState() => _RestoreBackupSheetState();
}

class _RestoreBackupSheetState extends State<_RestoreBackupSheet> {
  bool _loading = true;
  List<DateTime> _snapshots = const [];
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.service.listSnapshots();
    if (!mounted) return;
    setState(() {
      _snapshots = list;
      _loading = false;
    });
  }

  Future<void> _restore(DateTime takenAt) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
            'This replaces your current local data with the snapshot from '
            '${_format(takenAt)}. Your latest cloud data still wins on the next '
            'sync, so anything newer online is preserved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _restoring = true);
    final ok = await widget.service.restoreSnapshot(takenAt);
    if (ok) {
      // Reload every presenter from the freshly-restored local store.
      widget.storage.onRemoteDataApplied?.call();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (ok) {
      AppToast.success(
        messenger.context,
        'Restored your backup from ${_format(takenAt)}.',
      );
    } else {
      AppToast.error(
        messenger.context,
        'Could not restore that backup. Please try again.',
      );
    }
  }

  String _format(DateTime utc) =>
      DateFormat('MMM d, y · h:mm a').format(utc.toLocal());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Restore from cloud backup',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Immutable daily snapshots — pick one to roll back to.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_snapshots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: Text(
                    'No backups yet. They start the next time the app syncs.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _snapshots.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final at = _snapshots[i];
                    return ListTile(
                      leading: Icon(Icons.history,
                          color: theme.colorScheme.tertiary),
                      title: Text(_format(at)),
                      subtitle: i == 0 ? const Text('Most recent') : null,
                      trailing: _restoring
                          ? null
                          : const Icon(Icons.restore, size: 20),
                      onTap: _restoring ? null : () => _restore(at),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
