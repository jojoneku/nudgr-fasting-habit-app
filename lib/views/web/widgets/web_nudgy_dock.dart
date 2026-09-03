import 'package:flutter/material.dart';

import '../../../models/ai_coach_context.dart';
import '../../../presenters/ai_coach_presenter.dart';
import '../../../services/storage_service.dart';
import '../../widgets/ai_chat_sheet.dart';
import '../design/web_breakpoints.dart';
import 'web_shell.dart';

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

  /// Persists the width the user dragged the column to. Optional so the panel
  /// still works unstored (tests, previews) — it simply forgets between runs.
  final StorageService? storage;

  NudgyController(this.presenter, {this.storage}) {
    _restoreWidth();
  }

  /// Default open width. Wide enough for the header row and the chat body's
  /// four trailing controls; the reason the body hides its own entry label.
  static const double defaultWidth = 380;

  /// Narrowest the user can drag it. Below this the chat's own controls start
  /// ellipsising into each other, so the panel would be draggable into a state
  /// it cannot render — a resize handle should not be able to break the thing
  /// it resizes.
  static const double minWidth = 320;

  /// Widest, absent a window constraint. The view clamps further so the page
  /// always keeps a readable column; this is the ceiling for a huge display.
  static const double maxWidth = 900;

  bool _open = false;
  bool get isOpen => _open;

  double _width = defaultWidth;

  /// Current open width. Always within [minWidth]..[maxWidth]; the view
  /// additionally clamps it against the space the page can spare.
  double get width => _width;

  bool _isResizing = false;

  /// True while a drag is in flight, so the view can drop its width animation.
  /// An eased width during a drag lags the pointer, which reads as the handle
  /// slipping out of the user's grip rather than as smoothness.
  bool get isResizing => _isResizing;

  Future<void> _restoreWidth() async {
    final stored = await storage?.loadNudgyPanelWidth();
    if (stored == null) return;
    final clamped = stored.clamp(minWidth, maxWidth);
    if (clamped == _width) return;
    _width = clamped;
    notifyListeners();
  }

  void beginResize() {
    _isResizing = true;
    notifyListeners();
  }

  /// Applies a drag. [delta] is the pointer's horizontal movement; the panel is
  /// on the right, so dragging LEFT (negative dx) widens it.
  ///
  /// [available] is the most the shell can give up right now, already accounting
  /// for the page's own minimum. Passed in per-drag rather than stored because
  /// it changes with the window, and a width that was legal when the window was
  /// wide must not survive the window getting narrow.
  void applyResizeDelta(double delta, {required double available}) {
    // The view guarantees `available >= defaultWidth`, so the clamp range is
    // always valid and a narrow window can never pin the panel to its minimum.
    final next = (_width - delta).clamp(minWidth, available);
    if (next == _width) return;
    _width = next;
    notifyListeners();
  }

  void endResize() {
    _isResizing = false;
    notifyListeners();
    // Persist only on release. Writing on every drag frame would put a few
    // hundred writes through SharedPreferences for one gesture.
    storage?.saveNudgyPanelWidth(_width);
  }

  /// Returns the column to its default width. The handle is easy to nudge by a
  /// pixel or two without meaning to, and without this the only way back to a
  /// deliberate width is to drag until it looks right again.
  void resetWidth() {
    if (_width == defaultWidth) return;
    _width = defaultWidth;
    notifyListeners();
    storage?.saveNudgyPanelWidth(null);
  }

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
///
/// Resizable from its left edge. 380px is a good width for a question and a
/// bad one for the answer: the advisor replies with pipe tables — budget vs
/// actual per category, month vs month — and a table that has to scroll
/// sideways inside a narrow bubble is most of the way to unreadable. Rather
/// than pick one width for both jobs, the user drags.
class NudgyPanel extends StatelessWidget {
  final NudgyController controller;

  /// Default width of the open column. Retained as the historical name for
  /// [NudgyController.defaultWidth]; the live width now lives on the
  /// controller, since it is state the user owns.
  static const double openWidth = NudgyController.defaultWidth;

  /// Smallest the page may be squeezed to while the panel grows. The panel is
  /// a companion to the page, and a drag that reduces the page to a gutter has
  /// stopped serving the reason the panel is docked rather than floating.
  static const double _minPageWidth = 480;

  /// Hit width of the drag strip. Wider than the 1px border it sits on: an
  /// edge target has to be findable without precision aiming, and a 1px
  /// handle on a 380px panel is a hunt.
  static const double _handleWidth = 10;

  const NudgyPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        // How wide the panel is allowed to get right now. Recomputed on every
        // build so shrinking the window cannot leave a stored width that
        // crushes the page.
        // Note the floor is the DEFAULT width, not the minimum: the page's
        // reserve caps how far the panel may be GROWN, it does not squeeze the
        // panel below the width it opens at. A narrow window is a reason for
        // the page to be cramped, not for the conversation to be.
        // The window is rail + page + panel. Subtract the rail as well as the
        // page's reserve: measuring against the raw window width lets the
        // panel spend the rail's share, and the page ends up ~250px narrower
        // than the floor promises — cards truncate mid-figure.
        final spare = MediaQuery.sizeOf(context).width -
            WebShell.sidebarWidth -
            _minPageWidth;
        final maxNow = spare.clamp(
          NudgyController.defaultWidth,
          NudgyController.maxWidth,
        );
        final openWidthNow = controller.width.clamp(
          NudgyController.minWidth,
          maxNow,
        );
        final width = controller.isOpen ? openWidthNow : 0.0;
        return AnimatedContainer(
          // No easing while the pointer is down: an animated width lags the
          // drag and reads as the handle slipping out of the user's grip.
          duration: controller.isResizing
              ? Duration.zero
              : const Duration(milliseconds: 200),
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
              minWidth: openWidthNow,
              maxWidth: openWidthNow,
              child: controller.isOpen
                  ? Stack(
                      children: [
                        Positioned.fill(child: SafeArea(child: _body(context))),
                        // Left edge, above the content so the chat's own
                        // scrollables cannot swallow the horizontal drag.
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: _handleWidth,
                          child: _ResizeHandle(
                            controller: controller,
                            available: maxNow,
                          ),
                        ),
                      ],
                    )
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

/// The strip along Nudgy's left edge that resizes it.
///
/// Deliberately almost invisible until pointed at. A permanent grip line on a
/// panel the user mostly is not resizing is one more piece of furniture between
/// them and the conversation; the resize cursor already announces the affordance
/// to anyone who brushes the edge.
class _ResizeHandle extends StatefulWidget {
  final NudgyController controller;

  /// The widest the panel may become right now, passed down so the drag clamps
  /// against the live window rather than a remembered one.
  final double available;

  const _ResizeHandle({required this.controller, required this.available});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovered = false;

  /// Where the current click started, and when the last one that stayed still
  /// finished — the two facts needed to spot a double-click ourselves.
  ///
  /// The time comes from [PointerEvent.timeStamp], not the wall clock. Both are
  /// correct for a real user, but only the event's own stamp is the time base
  /// the framework advances, so a test that pumps 60ms of fake time between two
  /// clicks sees 60ms. Against `DateTime.now()` it saw however long the machine
  /// actually took, which under a loaded full-suite run drifted past the
  /// 300ms window and made the test flake.
  Offset? _downAt;
  Duration? _lastClickAt;

  /// How far a pointer may travel and still count as a click, not a drag.
  static const double _clickSlop = 4;

  /// Window for the second click of a double. Matches Flutter's own
  /// [kDoubleTapTimeout].
  static const Duration _doubleClickWindow = Duration(milliseconds: 300);

  // Double-click is detected from raw pointer events rather than with
  // GestureDetector's onDoubleTap, which does not survive contact with a real
  // mouse here. A mouse reports a pixel or two of jitter between press and
  // release, that is enough for the horizontal-drag recognizer sharing this
  // detector to claim the arena, and the double-tap recognizer is then
  // defeated before it can see the second click. It worked under test, where
  // synthetic pointers move exactly zero, and never once in a browser.
  //
  // A Listener sits outside the arena entirely, so it sees every press and
  // release regardless of which recognizer wins the gesture — and the drag
  // itself is excluded by distance, not by arena politics.
  void _onPointerDown(PointerDownEvent event) => _downAt = event.position;

  void _onPointerUp(PointerUpEvent event) {
    final down = _downAt;
    _downAt = null;
    if (down == null) return;
    if ((event.position - down).distance > _clickSlop) return; // a drag

    final now = event.timeStamp;
    final previous = _lastClickAt;
    _lastClickAt = now;
    if (previous == null || now - previous > _doubleClickWindow) {
      return;
    }
    // Consume it, so a third click does not read as another double.
    _lastClickAt = null;
    widget.controller.resetWidth();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _hovered || widget.controller.isResizing;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        child: GestureDetector(
          // opaque, so the strip takes the gesture even where it paints
          // nothing.
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => widget.controller.beginResize(),
          onHorizontalDragUpdate: (details) =>
              widget.controller.applyResizeDelta(
            details.delta.dx,
            available: widget.available,
          ),
          onHorizontalDragEnd: (_) => widget.controller.endResize(),
          onHorizontalDragCancel: widget.controller.endResize,
          child: Semantics(
            label: 'Resize Nudgy',
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: active ? 3 : 0,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
