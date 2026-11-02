import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/raw_capture.dart';
import 'package:intermittent_fasting/presenters/capture_inbox_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/date_utils.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import 'capture_disclosure_sheet.dart';

/// Settings ▸ Capture transactions: master toggle, system access status,
/// the source allowlist with a default account per source, remembered card
/// suffixes, and the privacy line. All state lives in the presenter.
Future<void> showCaptureSettingsSheet(
  BuildContext context, {
  required CaptureInboxPresenter presenter,
}) {
  return AppBottomSheet.show<void>(
    context: context,
    title: 'Capture transactions',
    useDraggableScrollableSheet: true,
    initialChildSize: 0.8,
    body: _SettingsBody(presenter: presenter),
  );
}

class _SettingsBody extends StatelessWidget {
  final CaptureInboxPresenter presenter;
  const _SettingsBody({required this.presenter});

  Future<void> _toggle(BuildContext context, bool value) async {
    if (!value) {
      await presenter.setEnabled(false);
      return;
    }
    if (!await showCaptureDisclosureSheet(context)) return;
    await presenter.setEnabled(true);
    if (!presenter.accessGranted) await presenter.openAccessSettings();
  }

  Future<void> _pickDefaultAccount(
      BuildContext context, String package, String label) async {
    final choice = await showAccountPicker(
      context,
      accounts: presenter.accounts,
      selectedId: presenter.settings.accountBySource[package],
      allowNone: true,
      noneLabel: 'Ask every time',
    );
    if (choice == null) return;
    await presenter.setSourceAccount(package, choice.id);
  }

  Future<void> _addFromRecent(BuildContext context) async {
    final apps = await presenter.recentApps();
    if (!context.mounted) return;
    final known = presenter.settings.sources;
    final candidates =
        apps.where((a) => !known.contains(a.packageName)).toList();
    final picked = await showModalBottomSheet<RecentApp>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const SheetTitle('Apps that posted recently'),
            if (candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Nothing new in the last 7 days. Notification access has to '
                  'be on for Nudgr to see which apps post.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in candidates)
                      ListTile(
                        leading: const Icon(Icons.apps_outlined),
                        title: Text(a.appLabel),
                        subtitle: Text(a.packageName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(relativeDayLabel(a.lastSeen)),
                        onTap: () => Navigator.of(ctx).pop(a),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await presenter.setSourceEnabled(picked.packageName, picked.appLabel, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final p = presenter;
        final s = p.settings;
        final muted =
            theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Capture from notifications'),
              subtitle: Text(
                p.isEnabled
                    ? 'Bank and e-wallet notifications land in the Inbox.'
                    : 'Off. Nothing is read.',
                style: muted,
              ),
              value: p.isEnabled,
              onChanged: (v) => _toggle(context, v),
            ),
            if (p.isEnabled) ...[
              const Divider(height: AppSpacing.lg),
              _StatusTile(presenter: p),
              const SizedBox(height: AppSpacing.md),
              AppSection(
                title: 'Sources',
                hint: 'Only these apps are kept. Set a default account so a '
                    'capture lands on it without asking.',
                trailing: TextButton.icon(
                  onPressed: () => _addFromRecent(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
                child: Column(
                  children: [
                    for (final row in p.sourceRows)
                      _SourceTile(
                        label: row.label,
                        package: row.package,
                        enabled: row.enabled,
                        accountName:
                            p.accountById(s.accountBySource[row.package])?.name,
                        senderHint: s.senderFilters[row.package]?.join(', '),
                        onToggle: (v) =>
                            p.setSourceEnabled(row.package, row.label, v),
                        onPickAccount: () => _pickDefaultAccount(
                            context, row.package, row.label),
                      ),
                  ],
                ),
              ),
              if (s.accountByLast4.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                AppSection(
                  title: 'Cards',
                  hint: 'Learned from your picks. A card suffix wins over the '
                      'app default.',
                  child: Column(
                    children: [
                      for (final e in s.accountByLast4.entries)
                        AppListTile(
                          dense: true,
                          leading: const Icon(Icons.credit_card_outlined),
                          title: Text('•••• ${e.key}'),
                          subtitle: Text(p.accountById(e.value)?.name ??
                              'Unknown account'),
                          trailing: IconButton(
                            tooltip: 'Forget',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => p.setLast4Account(e.key, null),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                'Notification text stays on this phone. It is sent to the '
                'cloud only when Cloud AI is on, and only for rows the parser '
                'could not finish. Nothing is added to the ledger until you '
                'approve it.',
                style: muted,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

/// Access granted / blocked, listener health, last capture.
class _StatusTile extends StatelessWidget {
  final CaptureInboxPresenter presenter;
  const _StatusTile({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = presenter;
    final granted = p.accessGranted;
    final asleep = p.listenerLooksAsleep;
    final last = p.lastCaptureAt;

    final Color tone;
    final IconData icon;
    final String title;
    final String body;
    if (!granted) {
      tone = cs.error;
      icon = Icons.notifications_off_outlined;
      title = 'Notification access is off';
      body = 'Android is not letting Nudgr read notifications yet. '
          'Tap to open the system page.';
    } else if (asleep) {
      tone = cs.tertiary;
      icon = Icons.bedtime_outlined;
      title = 'Listener looks asleep';
      body = 'It has not connected for over a day. A battery saver may have '
          'stopped it — reconnect, and allow Nudgr to run in the background.';
    } else {
      tone = cs.primary;
      icon = Icons.check_circle_outline;
      title = 'Listening';
      body = last == null
          ? 'No capture yet.'
          : 'Last capture ${relativeDayLabel(last).toLowerCase()}.';
    }

    return AppCard(
      color: cs.surfaceContainerLow,
      onTap: granted ? null : p.openAccessSettings,
      child: Row(
        children: [
          AppIconBadge(icon: icon, color: tone, size: 40, iconSize: 20),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (asleep)
            TextButton(
              onPressed: p.requestRebind,
              child: const Text('Reconnect'),
            )
          else if (!granted)
            const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final String label;
  final String package;
  final bool enabled;
  final String? accountName;

  /// Sender words the listener requires in the title ("BPI" for Gmail).
  final String? senderHint;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickAccount;

  const _SourceTile({
    required this.label,
    required this.package,
    required this.enabled,
    required this.accountName,
    this.senderHint,
    required this.onToggle,
    required this.onPickAccount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      title: Text(label),
      subtitle: enabled
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: onPickAccount,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      accountName == null
                          ? 'Default account: ask every time'
                          : 'Default account: $accountName',
                      style: TextStyle(
                        color: accountName == null ? cs.tertiary : cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (senderHint != null)
                  Text('Only senders: $senderHint',
                      style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            )
          : Text(package,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: Switch(value: enabled, onChanged: onToggle),
    );
  }
}
