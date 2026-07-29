import 'package:flutter/material.dart';

import '../../../models/ai_coach_context.dart';
import '../../../presenters/ai_coach_presenter.dart';
import '../../widgets/ai_chat_sheet.dart';
import '../design/web_breakpoints.dart';

/// Money Mentor as a persistent right-hand dock.
///
/// Mounted by the web shell across every destination rather than living on its
/// own page: the advisor's value is answering questions about the data you are
/// currently looking at, so navigating away from a bill to ask about it defeats
/// the point. Mobile's equivalent — a bottom sheet over the current screen —
/// already works this way.
///
/// Collapsed to a narrow rail by default so the wide tables keep their full
/// width; expanding overlays no content because the shell gives the dock its
/// own horizontal space (see [WebShell.dock]).
class WebAdvisorPanel extends StatefulWidget {
  final AiCoachPresenter presenter;

  /// Width of the expanded column.
  static const double expandedWidth = 380;

  /// Width of the collapsed rail.
  static const double railWidth = 56;

  const WebAdvisorPanel({super.key, required this.presenter});

  @override
  State<WebAdvisorPanel> createState() => _WebAdvisorPanelState();
}

class _WebAdvisorPanelState extends State<WebAdvisorPanel> {
  bool _open = false;

  /// Opened at least once this session — the presenter's advisor session is
  /// started lazily so a user who never opens the dock pays nothing for it.
  bool _sessionStarted = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && !_sessionStarted) {
      _sessionStarted = true;
      widget.presenter.openSession(AiCoachEntryPoint.financeAdvisor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width =
        _open ? WebAdvisorPanel.expandedWidth : WebAdvisorPanel.railWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      // Lay the contents out at their FINAL width and clip during the
      // transition, rather than letting them be squeezed into the intermediate
      // width. Without this the header row is handed ~32px on the first frames
      // of the expand and overflows.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: width,
          maxWidth: width,
          child: _open ? _expanded(context) : _collapsed(context),
        ),
      ),
    );
  }

  Widget _collapsed(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: WebInsets.lg),
        IconButton(
          tooltip: 'Open Money Mentor',
          onPressed: _toggle,
          icon: Icon(Icons.savings_outlined, color: cs.primary),
        ),
      ],
    );
  }

  Widget _expanded(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Collapse affordance only. The chat body's own header already supplies
        // the "Money Mentor" identity plus the conversations / memory /
        // thinking actions — titling this strip too would print the name twice.
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: WebInsets.xs),
            child: IconButton(
              tooltip: 'Collapse Money Mentor',
              visualDensity: VisualDensity.compact,
              onPressed: _toggle,
              icon: Icon(Icons.chevron_right,
                  size: 20, color: cs.onSurfaceVariant),
            ),
          ),
        ),
        Expanded(
          child: AiChatBody(
            presenter: widget.presenter,
            entryPoint: AiCoachEntryPoint.financeAdvisor,
            // No on-device tier on web — an unavailable model is terminal here,
            // so don't offer a download the platform can't perform.
            allowModelDownload: false,
          ),
        ),
      ],
    );
  }
}
