import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/alarm_notification.dart';
import '../../presenters/quest_alarm_presenter.dart';
import '../../utils/app_spacing.dart';

/// The screen a full-screen alarm notification opens.
///
/// This is the *only* surface allowed to draw over the lock screen, so it shows
/// nothing but the reminder itself — no Hub, no balances, no navigation into
/// the rest of the app. Dismissing it hands the keyguard straight back.
class QuestAlarmScreen extends StatefulWidget {
  const QuestAlarmScreen({
    super.key,
    required this.alarm,
    this.presenter,
  });

  final AlarmNotification alarm;

  /// Injected in tests; built from [alarm] otherwise.
  final QuestAlarmPresenter? presenter;

  @override
  State<QuestAlarmScreen> createState() => _QuestAlarmScreenState();
}

class _QuestAlarmScreenState extends State<QuestAlarmScreen> {
  late final QuestAlarmPresenter _presenter;
  late final bool _ownsPresenter;

  @override
  void initState() {
    super.initState();
    _ownsPresenter = widget.presenter == null;
    _presenter =
        widget.presenter ?? QuestAlarmPresenter(alarm: widget.alarm);
    _presenter.closeRequest.addListener(_onCloseRequested);
    _presenter.init();
  }

  void _onCloseRequested() {
    final how = _presenter.closeRequest.value;
    if (how == null || !mounted) return;
    switch (how) {
      case AlarmDismissal.returnToLockScreen:
        // Finish the activity rather than popping to the page underneath —
        // that page is behind the keyguard and must stay there.
        SystemNavigator.pop();
      case AlarmDismissal.popRoute:
        Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _presenter.closeRequest.removeListener(_onCloseRequested);
    if (_ownsPresenter) _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      // Back must go through the presenter so the lock-screen flags are
      // released; letting the route pop on its own would leave them set.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _presenter.dismiss();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _presenter,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Upper 70%: the reminder, and nothing else ──────────
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _presenter.timeLabel,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Icon(
                          _presenter.isQuest
                              ? Icons.alarm_on_outlined
                              : Icons.emoji_events_outlined,
                          size: 44,
                          color: cs.primary,
                        ),
                        const SizedBox(height: AppSpacing.mdGenerous),
                        Text(
                          _presenter.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(color: cs.onSurface),
                        ),
                        if (_presenter.body.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _presenter.body,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Bottom 30%: the actions ───────────────────────────
                  if (_presenter.isQuest) ...[
                    _AlarmAction(
                      label: 'Mark as Done',
                      onPressed: _presenter.markDone,
                      filled: true,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _AlarmAction(
                      label: 'Snooze ${_presenter.snoozeMinutes}m',
                      onPressed: _presenter.snooze,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  _AlarmAction(
                    label: 'Dismiss',
                    onPressed: _presenter.dismiss,
                    filled: !_presenter.isQuest,
                    quiet: _presenter.isQuest,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width alarm button. Height is pinned above the 44px minimum because
/// these get tapped half-asleep, on a locked phone.
class _AlarmAction extends StatelessWidget {
  const _AlarmAction({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
    );
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    if (quiet) {
      return TextButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}
