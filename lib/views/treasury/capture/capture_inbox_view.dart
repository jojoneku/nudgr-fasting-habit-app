import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/captured_transaction.dart';
import 'package:intermittent_fasting/presenters/capture_inbox_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/date_utils.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import 'capture_disclosure_sheet.dart';
import 'capture_row.dart';
import 'capture_settings_sheet.dart';

/// The Capture Inbox: captured notifications waiting for a decision, grouped
/// by day, newest first. Approve and Decline each show an Undo toast.
///
/// Every decision goes through [CaptureInboxPresenter]; this page renders
/// the five states it can be in (unsupported, off, no access, empty, list)
/// and forwards taps. See `.claude/plans/070-capture-inbox.md` §2.
class CaptureInboxView extends StatefulWidget {
  final CaptureInboxPresenter presenter;
  const CaptureInboxView({super.key, required this.presenter});

  @override
  State<CaptureInboxView> createState() => _CaptureInboxViewState();
}

class _CaptureInboxViewState extends State<CaptureInboxView> {
  CaptureInboxPresenter get p => widget.presenter;

  @override
  void initState() {
    super.initState();
    // Opening the inbox is the moment to pick up whatever the listener
    // queued since the last foreground.
    p.refreshAccess();
    p.drain();
  }

  Future<void> _turnOn() async {
    if (!await showCaptureDisclosureSheet(context)) return;
    await p.setEnabled(true);
    if (!p.accessGranted) await p.openAccessSettings();
  }

  Future<void> _grantAccess() async {
    if (!await showCaptureDisclosureSheet(context)) return;
    await p.openAccessSettings();
  }

  Future<void> _approve(CapturedTransaction item) async {
    try {
      final posted = await p.approve(item.id);
      if (!mounted || posted == null) return;
      final twins = p.lastAutoDeclinedLabels;
      final twinNote =
          twins.isEmpty ? '' : ' · ${twins.join(', ')} duplicate declined';
      AppToast.action(
        context,
        message:
            'Added ${formatPeso(posted.amount)} · ${posted.description}$twinNote',
        actionLabel: 'Undo',
        onAction: () => p.undo(item.id),
        duration: const Duration(seconds: 5),
      );
    } on StateError {
      if (!mounted) return;
      final first = item.missing.isEmpty ? null : item.missing.first;
      AppToast.error(
          context,
          first == null
              ? 'This row is not ready yet'
              : 'Needs ${first.label.toLowerCase()} first');
    }
  }

  Future<void> _decline(CapturedTransaction item) async {
    await p.decline(item.id);
    if (!mounted) return;
    AppToast.action(
      context,
      message: 'Declined',
      actionLabel: 'Undo',
      onAction: () => p.undo(item.id),
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _approveAll() async {
    final n = await p.approveAllReady();
    if (!mounted) return;
    AppToast.success(context, 'Added $n transaction${n == 1 ? '' : 's'}');
  }

  Future<void> _declineAll() async {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: 'Decline everything?',
      body: 'All ${p.pendingCount} waiting rows will be declined. '
          'Nothing is added to the ledger.',
      confirmLabel: 'Decline all',
      isDestructive: true,
    );
    if (!ok) return;
    await p.declineAll();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final ready = p.readyCount;
        return AppPageScaffold(
          title: 'Inbox',
          padding: EdgeInsets.zero,
          actions: [
            if (ready > 0)
              TextButton(
                onPressed: _approveAll,
                child: Text('Approve all ready ($ready)'),
              ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                switch (v) {
                  case 'sources':
                    showCaptureSettingsSheet(context, presenter: p);
                  case 'decline_all':
                    _declineAll();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                    value: 'sources', child: Text('Sources & settings')),
                if (p.pendingCount > 0)
                  const PopupMenuItem(
                      value: 'decline_all', child: Text('Decline all')),
              ],
            ),
          ],
          body: _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!p.isSupported) {
      return const AppEmptyState(
        icon: Icons.phone_android_outlined,
        title: 'Android only',
        body: 'Notification capture needs Android. The inbox still shows '
            'rows synced from your phone.',
      );
    }
    if (!p.isEnabled) {
      return AppEmptyState(
        icon: Icons.move_to_inbox_outlined,
        title: 'Capture is off',
        body: 'Turn it on and Nudgr files bank and e-wallet notifications '
            'here as drafts for you to approve.',
        actionLabel: 'Turn on capture',
        onAction: _turnOn,
      );
    }
    if (!p.accessGranted) {
      return AppEmptyState(
        icon: Icons.notifications_paused_outlined,
        title: 'Notification access needed',
        body: 'Android has to let Nudgr read notifications from the apps you '
            'picked. Nothing is kept from any other app.',
        actionLabel: 'Enable notification access',
        onAction: _grantAccess,
      );
    }

    final rows = p.pending;
    if (rows.isEmpty) {
      final last = p.lastCaptureAt;
      return AppEmptyState(
        icon: Icons.inbox_outlined,
        title: 'Nothing to review',
        body: last == null
            ? 'No notification has been captured yet. Pay with one of your '
                'sources and come back.'
            : 'Last capture ${relativeDayLabel(last).toLowerCase()}. '
                'New ones land here as they arrive.',
      );
    }

    // Day headers, newest first; rows keep their own key so an approve or
    // decline removes exactly that card.
    final children = <Widget>[];
    DateTime? day;
    for (final item in rows) {
      final d = DateTime(
          item.capturedAt.year, item.capturedAt.month, item.capturedAt.day);
      if (day != d) {
        day = d;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
          child: Text(
            relativeDayLabel(d),
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ));
      }
      children.add(Padding(
        key: ValueKey(item.id),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: Dismissible(
          key: ValueKey('swipe-${item.id}'),
          background: _SwipeBackground(
            alignment: Alignment.centerLeft,
            color: cs.tertiaryContainer,
            icon: Icons.check_rounded,
            label: 'Approve',
            foreground: cs.onTertiaryContainer,
          ),
          secondaryBackground: _SwipeBackground(
            alignment: Alignment.centerRight,
            color: cs.surfaceContainerHighest,
            icon: Icons.close_rounded,
            label: 'Decline',
            foreground: cs.onSurfaceVariant,
          ),
          // The action itself removes the row from [pending]; returning
          // false keeps Dismissible from also tearing the widget down.
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await _approve(item);
            } else {
              await _decline(item);
            }
            return false;
          },
          child: CaptureRow(
            presenter: p,
            item: item,
            onApprove: () => _approve(item),
            onDecline: () => _decline(item),
          ),
        ),
      ));
    }
    children.add(const SizedBox(height: AppSpacing.xxl));
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: children,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;

  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Text(label,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
