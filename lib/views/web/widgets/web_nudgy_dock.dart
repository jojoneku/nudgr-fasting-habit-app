import 'package:flutter/material.dart';

import '../../../models/ai_coach_context.dart';
import '../../../presenters/ai_coach_presenter.dart';
import '../../widgets/ai_chat_sheet.dart';
import '../design/web_breakpoints.dart';

/// Nudgy — the one place on web where you type at the app.
///
/// It used to be two boxes. A Quick Add popover on the Ledger page parsed a
/// transaction and logged it; a separate advisor dock answered questions. Both
/// took typed money-talk, and which one you happened to be in front of decided
/// whether you were logging or asking. Worse, the advisor had no clarify UI in
/// the popover, so Quick Add had to run a one-shot mode of its own.
///
/// There is one input now. [AiCoachPresenter.send] routes it: something that
/// reads as a transaction goes through the ledger's confirm-before-commit
/// pipeline and comes back as a confirm card; anything else is a question for
/// the advice model. So "207 lunch at alturas maya credit card" logs and "how
/// much on food this month?" answers, from the same box, with no mode to pick.
///
/// The name dropped "Money Mentor" along the way: once it both logs and
/// advises, "mentor" describes half the job.
///
/// Split into a launcher and a panel because they sit in different places. The
/// panel is a column in the shell's row — it takes its own width so the page
/// keeps its full layout budget rather than being overlaid. The launcher floats
/// over the content, bottom-right, which is where the Quick Add button was and
/// therefore where the muscle memory is. [NudgyController] is what keeps them
/// agreeing.
class NudgyController extends ChangeNotifier {
  final AiCoachPresenter presenter;

  NudgyController(this.presenter);

  bool _open = false;
  bool get isOpen => _open;

  /// The advisor session is started on first open, not at construction: a user
  /// who never opens Nudgy should not pay for building its context.
  bool _sessionStarted = false;

  void toggle() => _open ? close() : open();

  void open() {
    if (_open) return;
    _open = true;
    if (!_sessionStarted) {
      _sessionStarted = true;
      presenter.openSession(AiCoachEntryPoint.financeAdvisor);
    }
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }
}

/// The floating button that opens Nudgy. Hidden while the panel is open, so the
/// only way to dismiss is the panel's own collapse control — two competing
/// close affordances read as a stuck dialog.
class NudgyLauncher extends StatelessWidget {
  final NudgyController controller;
  const NudgyLauncher({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: controller.isOpen ? 0 : 1,
          child: FloatingActionButton.extended(
            heroTag: 'nudgy',
            onPressed: controller.open,
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            // Labelled, not a bare glyph. The advisor was previously a 56px
            // rail holding one unlabelled icon, and it read as decoration —
            // "unreachable" was the report, from someone who had it on screen.
            icon: const Icon(Icons.auto_awesome, size: 20),
            label: const Text('Ask Nudgy'),
            tooltip: 'Log a transaction or ask about your money',
          ),
        );
      },
    );
  }
}

/// Nudgy's conversation column. Zero-width while closed, so the shell can keep
/// it mounted in the row unconditionally and the page gets the space back.
class NudgyPanel extends StatelessWidget {
  final NudgyController controller;

  /// Width of the open column.
  static const double openWidth = 380;

  const NudgyPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final width = controller.isOpen ? openWidth : 0.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: width,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(
              left: BorderSide(
                color: cs.outlineVariant.withValues(
                  alpha: controller.isOpen ? 0.5 : 0,
                ),
              ),
            ),
          ),
          // Lay the contents out at their FINAL width and clip during the
          // transition, rather than letting them be squeezed into the
          // intermediate width — the header row is handed a few pixels on the
          // first frames of the expand and would overflow.
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: openWidth,
              maxWidth: openWidth,
              child: controller.isOpen
                  ? SafeArea(child: _body(context))
                  : const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Title + collapse. The chat body below keeps the entry icon and the
        // conversations / memory / thinking controls but drops its own label
        // (`showEntryLabel: false`) — at 380px that label competes with four
        // trailing controls and ellipsises. Printing it here keeps one title,
        // in the place that has room for it.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              WebInsets.lg, WebInsets.sm, WebInsets.xs, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Nudgy',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Collapse Nudgy',
                visualDensity: VisualDensity.compact,
                onPressed: controller.close,
                icon: Icon(Icons.chevron_right,
                    size: 20, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: AiChatBody(
            presenter: controller.presenter,
            entryPoint: AiCoachEntryPoint.financeAdvisor,
            showEntryLabel: false,
            // No on-device tier on web — an unavailable model is terminal here,
            // so don't offer a download the platform cannot perform.
            allowModelDownload: false,
          ),
        ),
      ],
    );
  }
}
