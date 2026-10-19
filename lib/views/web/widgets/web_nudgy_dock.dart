import 'package:flutter/material.dart';

import '../../../models/ai_coach_context.dart';
import '../../../presenters/ai_coach_presenter.dart';
import '../../../services/storage_service.dart';
import '../../widgets/advisor_memory_sheet.dart';
import '../../widgets/ai_chat_sheet.dart';
import '../design/web_breakpoints.dart';
import '../web_keys.dart';
import 'web_shell.dart';
import 'web_shell_v2.dart';

/// The input placeholder the web gives Nudgy. Mobile keeps the presenter's
/// own "Ask your coach…": on web the one box both logs and advises, and the
/// hint is where a first-time user learns that.
const String kNudgyWebInputHint = 'Log a transaction or ask about your money…';

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

  bool _hasCustomWidth = false;

  /// True once the user has dragged Nudgy to a width of their own (this run or
  /// a stored one). Until then the Dashboard rail sizes itself to the window;
  /// a double-click on the handle returns it to that automatic width.
  bool get hasCustomWidth => _hasCustomWidth;

  Future<void> _restoreWidth() async {
    final stored = await storage?.loadNudgyPanelWidth();
    if (stored == null) return;
    _hasCustomWidth = true;
    _width = stored.clamp(minWidth, maxWidth);
    notifyListeners();
  }

  /// Starts a drag. [from] is the width on screen when it differs from
  /// [width] — the Dashboard rail sizes itself until first dragged, and the
  /// drag must start from what the user sees, not from a stale default.
  void beginResize({double? from}) {
    if (from != null) _width = from.clamp(minWidth, maxWidth);
    _widthAtResizeStart = _width;
    _isResizing = true;
    notifyListeners();
  }

  /// The width when the current drag began. A click on the handle (the drag
  /// recognizer starts and ends with no movement when it is alone in the
  /// arena) leaves the width here, and must not count as choosing one.
  double _widthAtResizeStart = defaultWidth;

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
    // A plain click on the handle fires the drag recognizer's cancel too; with
    // no drag in flight there is nothing to end, and treating it as one would
    // undo the double-click reset that click belongs to.
    if (!_isResizing) return;
    _isResizing = false;
    if (_width == _widthAtResizeStart) {
      // A click, not a drag: nothing was chosen, nothing to save.
      notifyListeners();
      return;
    }
    _hasCustomWidth = true;
    notifyListeners();
    // Persist only on release. Writing on every drag frame would put a few
    // hundred writes through SharedPreferences for one gesture.
    storage?.saveNudgyPanelWidth(_width);
  }

  /// Returns the column to its default width. The handle is easy to nudge by a
  /// pixel or two without meaning to, and without this the only way back to a
  /// deliberate width is to drag until it looks right again.
  void resetWidth() {
    // The reset's own click opened a zero-length "drag" (see endResize); end
    // it here so its release cannot mark the width custom again.
    _isResizing = false;
    if (_width == defaultWidth && !_hasCustomWidth) return;
    _width = defaultWidth;
    _hasCustomWidth = false;
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
    ensureSession();
    notifyListeners();
  }

  /// Starts the advisor session if it has not been started. Called by [open],
  /// and by the always-visible [NudgyRail] when it mounts — the rail has no
  /// open/closed state of its own, but the conversation behind it still has
  /// to exist before the first message.
  void ensureSession() {
    if (_sessionStarted) return;
    _sessionStarted = true;
    presenter.openSession(AiCoachEntryPoint.financeAdvisor);
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

/// The v2 "Ask Nudgy" control: a 40 × 40 filled primary icon button that sits
/// in a page header and toggles the slide-over [NudgyPanel]. Replaces the
/// floating [NudgyLauncher] on the v2 path, where a page header is the one
/// place every page already has for its controls and nothing floats over the
/// content.
class NudgyHeaderButton extends StatelessWidget {
  final NudgyController controller;
  const NudgyHeaderButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Semantics(
        toggled: controller.isOpen,
        child: IconButton.filled(
          key: WebKeys.nudgyOpen,
          tooltip: 'Ask Nudgy',
          onPressed: controller.toggle,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.auto_awesome, size: 18),
        ),
      ),
    );
  }
}

/// Nudgy as a fixed column (the Dashboard's right rail, ≥ 1280 px): one card
/// holding a single header row — title, Think/Fast, Conversations, Advisor
/// memory — the conversation, a row of quick-action chips and the input.
///
/// Built on [AiChatBody] with its own header hidden (`compactHeader`), so the
/// column has one title row rather than the two the slide-over used to show.
/// Always visible, so it has no open/closed state; it starts the advisor
/// session itself when it mounts.
class NudgyRail extends StatefulWidget {
  final NudgyController controller;

  /// Opens the receipt dialog ("Scan a receipt" chip). The other two chips
  /// send their text to Nudgy as a message.
  final VoidCallback onScanReceipt;

  const NudgyRail({
    super.key,
    required this.controller,
    required this.onScanReceipt,
  });

  @override
  State<NudgyRail> createState() => _NudgyRailState();
}

class _NudgyRailState extends State<NudgyRail> {
  @override
  void initState() {
    super.initState();
    widget.controller.ensureSession();
  }

  @override
  Widget build(BuildContext context) {
    // The card fills the rail column the shell gives it. A drag handle on its
    // left edge resizes that column, the same way the slide-over panel's does;
    // the column is the card plus the shell's 40 px right padding.
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = MediaQuery.sizeOf(context).width;
        final available =
            (window - WebShellV2.navWidth - WebShellV2.minPageWidthBesideRail)
                .clamp(NudgyController.minWidth, NudgyController.maxWidth)
                .toDouble();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: _card(context)),
            Positioned(
              left: -NudgyPanel._handleWidth,
              top: 0,
              bottom: 0,
              width: NudgyPanel._handleWidth * 1.5,
              child: _ResizeHandle(
                controller: widget.controller,
                available: available,
                currentWidth: () =>
                    constraints.maxWidth + WebShellV2.railRightPadding,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final presenter = widget.controller.presenter;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nudgy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                KeyedSubtree(
                  key: WebKeys.nudgyThinkingToggle,
                  child: AiThinkingToggle(presenter: presenter),
                ),
                const SizedBox(width: 2),
                IconButton(
                  key: WebKeys.nudgyConversations,
                  tooltip: 'Conversations',
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: () =>
                      AiChatBody.showConversations(context, presenter),
                  icon: Icon(Icons.forum_outlined,
                      size: 20, color: cs.onSurfaceVariant),
                ),
                IconButton(
                  key: WebKeys.nudgyMemory,
                  tooltip: 'Advisor memory',
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: () => AdvisorMemorySheet.show(context, presenter),
                  icon: Icon(Icons.bookmark_border,
                      size: 20, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: AiChatBody(
              presenter: presenter,
              entryPoint: AiCoachEntryPoint.financeAdvisor,
              showEntryLabel: false,
              compactHeader: true,
              allowModelDownload: false,
              inputHint: kNudgyWebInputHint,
              // Conversation starters: gone once the user has said something,
              // back with a new conversation (see showsQuickActions).
              aboveInput: ListenableBuilder(
                listenable: presenter,
                builder: (_, chips) => Visibility(
                  visible: presenter.showsQuickActions,
                  child: chips!,
                ),
                child: _QuickActions(
                  presenter: presenter,
                  onScanReceipt: widget.onScanReceipt,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three quick-action chips above the rail's input.
class _QuickActions extends StatelessWidget {
  final AiCoachPresenter presenter;
  final VoidCallback onScanReceipt;

  const _QuickActions({required this.presenter, required this.onScanReceipt});

  static const String payCard = 'Pay a card';
  static const String spendToday = 'What can I spend today?';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        final canSend = presenter.isModelAvailable &&
            !presenter.isResponding &&
            !presenter.isInitializing;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuickChip(
                key: WebKeys.nudgyChipScanReceipt,
                label: 'Scan a receipt',
                onTap: onScanReceipt,
              ),
              _QuickChip(
                key: WebKeys.nudgyChipPayCard,
                label: payCard,
                onTap: canSend ? () => presenter.send(payCard) : null,
              ),
              _QuickChip(
                key: WebKeys.nudgyChipSpendToday,
                label: spendToday,
                onTap: canSend ? () => presenter.send(spendToday) : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _QuickChip({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ActionChip(
      label: Text(label),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: onTap == null ? cs.onSurfaceVariant : cs.onSurface,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      backgroundColor: cs.surfaceContainerHigh,
      disabledColor: cs.surfaceContainerHigh,
      side: BorderSide(color: cs.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: onTap,
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

  /// The v2 shell's look: one header row carrying the title, Think/Fast,
  /// Conversations, Advisor memory and Collapse, over a chat body with its
  /// own header hidden — the same row [NudgyRail] draws, so the slide-over
  /// and the Dashboard column read as one control. Off by default so the
  /// pre-v2 shell keeps its two-row panel until Phase 11 removes it.
  final bool compact;

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

  const NudgyPanel({
    super.key,
    required this.controller,
    this.compact = false,
  });

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
    if (compact) return _compactBody(context);
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

  /// One header row (mirrors [NudgyRail]) and the chat body underneath.
  Widget _compactBody(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final presenter = controller.presenter;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nudgy',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              KeyedSubtree(
                key: WebKeys.nudgyThinkingToggle,
                child: AiThinkingToggle(presenter: presenter),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: WebKeys.nudgyConversations,
                tooltip: 'Conversations',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () =>
                    AiChatBody.showConversations(context, presenter),
                icon: Icon(Icons.forum_outlined,
                    size: 20, color: cs.onSurfaceVariant),
              ),
              IconButton(
                key: WebKeys.nudgyMemory,
                tooltip: 'Advisor memory',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => AdvisorMemorySheet.show(context, presenter),
                icon: Icon(Icons.bookmark_border,
                    size: 20, color: cs.onSurfaceVariant),
              ),
              IconButton(
                key: WebKeys.nudgyClose,
                tooltip: 'Collapse Nudgy',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: controller.close,
                icon: Icon(Icons.chevron_right,
                    size: 20, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: AiChatBody(
            presenter: presenter,
            entryPoint: AiCoachEntryPoint.financeAdvisor,
            showEntryLabel: false,
            compactHeader: true,
            // No on-device tier on web — an unavailable model is terminal
            // here, so don't offer a download the platform cannot perform.
            allowModelDownload: false,
            inputHint: kNudgyWebInputHint,
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

  /// The width on screen when a drag starts, if it is not
  /// [NudgyController.width] (the Dashboard rail before its first drag).
  final double Function()? currentWidth;

  const _ResizeHandle({
    required this.controller,
    required this.available,
    this.currentWidth,
  });

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
          onHorizontalDragStart: (_) =>
              widget.controller.beginResize(from: widget.currentWidth?.call()),
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
