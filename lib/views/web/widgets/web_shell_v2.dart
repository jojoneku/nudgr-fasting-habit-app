import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../presenters/sync_presenter.dart';
import '../design/web_breakpoints.dart';
import '../design/web_dest.dart';
import '../web_keys.dart';

/// The Treasury web v2 desktop shell (Plan 063, Phase 1).
///
/// A 232 px nav rail grouped Overview · Money · Plan · Review, with Setup &
/// Accounts, the sync line, the theme toggle and the account row in its foot;
/// then the page, in a column capped at [WebBreakpoints.contentV2]; then,
/// optionally, a fixed right rail (the Dashboard's Nudgy) or the slide-over
/// dock. There is no top bar: the page header is the only title on the page.
///
/// Built from plain values and callbacks rather than presenters so it can be
/// rendered in a test with no graph behind it. The old [WebShell] is left as
/// it was for the non-flag path.
class WebShellV2 extends StatelessWidget {
  /// Width of the nav rail. Named so the Nudgy dock can subtract it when it
  /// works out how much width the page can spare.
  static const double navWidth = 232;

  /// The page never gets narrower than this beside the right rail; a rail
  /// dragged wider is clamped so the page keeps it.
  static const double minPageWidthBesideRail = 640;

  /// Right padding inside the rail column (the card sits inside it).
  static const double railRightPadding = 40;

  /// The rail column's width the user dragged to (Nudgy's saved width), or
  /// null for the automatic [railWidthFor] the window.
  final double? rightRailWidth;

  final WebDest selected;
  final ValueChanged<WebDest> onSelect;

  /// The page.
  final Widget child;

  /// A column fixed beside the page at [WebBreakpoints.rightRail] and wider
  /// (the Dashboard passes the Nudgy rail). Below that width it is not shown
  /// and [dock] is used instead.
  final Widget? rightRail;

  /// The slide-over Nudgy panel. Mounted when [rightRail] is null or the
  /// window is too narrow for it. Owns its own width (zero while closed).
  final Widget? dock;

  /// Unpaid bills this month, shown as a pill on the Bills item. Hidden at 0.
  final int billsDueCount;

  /// Sync state for the foot of the rail. Null hides the row (sync not
  /// running, or it failed to start).
  final SyncPresenter? sync;

  /// Signed-in account. The row shows [displayName], or the local part of
  /// [email] when there is no name; the menu shows the full email.
  final String? email;
  final String? displayName;
  final VoidCallback onSignOut;

  /// Extra footer row above the account (the app lock's Security / Lock
  /// now). Null shows nothing.
  final Widget? footerExtra;

  final bool isDark;
  final VoidCallback onToggleTheme;

  const WebShellV2({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.child,
    this.rightRail,
    this.rightRailWidth,
    this.dock,
    this.billsDueCount = 0,
    this.sync,
    this.email,
    this.displayName,
    required this.onSignOut,
    this.footerExtra,
    required this.isDark,
    required this.onToggleTheme,
  });

  /// The Nudgy rail's width for a window [windowWidth] wide: about a quarter
  /// of the window, so it grows on wide screens and never squeezes the page
  /// on a laptop. Between [minRailWidth] and [maxRailWidth].
  static double railWidthFor(double windowWidth) =>
      (windowWidth * 0.24).clamp(minRailWidth, maxRailWidth).toDouble();

  /// The rail column: the user's dragged width when there is one, else
  /// automatic — and never so wide the page drops under
  /// [minPageWidthBesideRail].
  double _railWidth(double windowWidth) {
    final most = windowWidth - navWidth - minPageWidthBesideRail;
    final want = rightRailWidth ?? railWidthFor(windowWidth);
    return want
        .clamp(minRailWidth.clamp(0, most), most.clamp(0, double.infinity))
        .toDouble();
  }

  static const double minRailWidth = 340;
  static const double maxRailWidth = 440;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windowWidth = MediaQuery.sizeOf(context).width;
    final showRail =
        rightRail != null && windowWidth >= WebBreakpoints.rightRail;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavRail(
            selected: selected,
            onSelect: onSelect,
            billsDueCount: billsDueCount,
            sync: sync,
            email: email,
            displayName: displayName,
            onSignOut: onSignOut,
            footerExtra: footerExtra,
            isDark: isDark,
            onToggleTheme: onToggleTheme,
          ),
          // The page fills the width beside the rail (or the window edge) up
          // to WebBreakpoints.contentV2, and centres past that on very wide
          // screens — no dead strip between the page and Nudgy.
          Expanded(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: WebBreakpoints.contentV2),
                  child: Padding(
                    padding:
                        EdgeInsets.fromLTRB(40, 28, showRail ? 24 : 40, 48),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
          if (showRail)
            SizedBox(
              width: _railWidth(windowWidth),
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(0, 28, railRightPadding, 48),
                  child: rightRail,
                ),
              ),
            )
          else if (dock != null)
            dock!,
        ],
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  final WebDest selected;
  final ValueChanged<WebDest> onSelect;
  final int billsDueCount;
  final SyncPresenter? sync;
  final String? email;
  final String? displayName;
  final VoidCallback onSignOut;

  /// Extra footer row above the account (the app lock's Security / Lock
  /// now). Null shows nothing.
  final Widget? footerExtra;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const _NavRail({
    required this.selected,
    required this.onSelect,
    required this.billsDueCount,
    required this.sync,
    required this.email,
    required this.displayName,
    required this.onSignOut,
    this.footerExtra,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: WebShellV2.navWidth,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Brand(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in WebNavGroup.values) ...[
                        _GroupLabel(group.label),
                        for (final dest in WebDest.inGroup(group))
                          _NavItem(
                            dest: dest,
                            selected: dest == selected,
                            onTap: () => onSelect(dest),
                            count: dest == WebDest.bills ? billsDueCount : 0,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              _NavFoot(
                selected: selected,
                onSelect: onSelect,
                sync: sync,
                email: email,
                displayName: displayName,
                onSignOut: onSignOut,
                footerExtra: footerExtra,
                isDark: isDark,
                onToggleTheme: onToggleTheme,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 18),
      child: Row(
        children: [
          Image.asset(
            'assets/img/nudgr_icon_nobg_colored.png',
            width: 28,
            height: 28,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Treasury',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.34,
                    height: 1.2,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Nudgr · web',
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.appColors.textMuted,
        ),
      ),
    );
  }
}

/// One rail entry: 40 px tall, radius 12, selected = primary tint + primary
/// text at w700, hover = onSurface at 5 %. [count] > 0 draws the due pill.
class _NavItem extends StatefulWidget {
  final WebDest dest;
  final bool selected;
  final VoidCallback onTap;
  final int count;

  const _NavItem({
    required this.dest,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  static Key keyFor(WebDest dest) => switch (dest) {
        WebDest.dashboard => WebKeys.navDashboard,
        WebDest.ledger => WebKeys.navLedger,
        WebDest.bills => WebKeys.navBills,
        WebDest.budget => WebKeys.navBudget,
        WebDest.history => WebKeys.navHistory,
        WebDest.goals => WebKeys.navGoals,
        WebDest.setup => WebKeys.navSetup,
      };

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = widget.selected;
    final fg = selected
        ? cs.primary
        : _hover
            ? cs.onSurface
            : cs.onSurfaceVariant;
    final bg = selected
        ? cs.primary.withValues(alpha: 0.14)
        : _hover
            ? cs.onSurface.withValues(alpha: 0.05)
            : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.dest.label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            key: _NavItem.keyFor(widget.dest),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? widget.dest.selectedIcon : widget.dest.icon,
                    size: 18,
                    color: fg,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.dest.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.count > 0) _DuePill(count: widget.count),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "3 due" in the bills (warning) tint.
class _DuePill extends StatelessWidget {
  final int count;
  const _DuePill({required this.count});

  @override
  Widget build(BuildContext context) {
    final bills = context.appColors.bills;
    return Container(
      key: WebKeys.navBillsDuePill,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bills.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count due',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: bills,
              height: 1.3,
            ),
      ),
    );
  }
}

class _NavFoot extends StatelessWidget {
  final WebDest selected;
  final ValueChanged<WebDest> onSelect;
  final SyncPresenter? sync;
  final String? email;
  final String? displayName;
  final VoidCallback onSignOut;

  /// Extra footer row above the account (the app lock's Security / Lock
  /// now). Null shows nothing.
  final Widget? footerExtra;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const _NavFoot({
    required this.selected,
    required this.onSelect,
    required this.sync,
    required this.email,
    required this.displayName,
    required this.onSignOut,
    this.footerExtra,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavItem(
            dest: WebDest.setup,
            selected: selected == WebDest.setup,
            onTap: () => onSelect(WebDest.setup),
          ),
          const SizedBox(height: 6),
          _SyncRow(
            sync: sync,
            isDark: isDark,
            onToggleTheme: onToggleTheme,
          ),
          if (footerExtra != null) ...[
            const SizedBox(height: 6),
            footerExtra!,
          ],
          const SizedBox(height: 6),
          _AccountRow(
            email: email,
            displayName: displayName,
            onSignOut: onSignOut,
          ),
        ],
      ),
    );
  }
}

/// Status dot + label, with the theme toggle at the right. The label and dot
/// are hidden when there is no sync (the toggle stays).
class _SyncRow extends StatelessWidget {
  final SyncPresenter? sync;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const _SyncRow({
    required this.sync,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sync = this.sync;
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        children: [
          Expanded(
            child: sync == null
                ? const SizedBox.shrink()
                : ListenableBuilder(
                    listenable: sync,
                    builder: (context, _) {
                      final failed = sync.syncError != null;
                      final color = failed ? cs.error : cs.onSurfaceVariant;
                      return Row(
                        key: WebKeys.navSyncStatus,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  failed ? cs.error : context.appColors.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              failed ? 'Sync failed' : sync.statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                color: color,
                                fontWeight:
                                    failed ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          IconButton(
            key: WebKeys.navThemeToggle,
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: onToggleTheme,
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar initial + name + "Sign out" hint; opens a menu with the full email
/// (not selectable) and the Sign out action.
class _AccountRow extends StatelessWidget {
  final String? email;
  final String? displayName;
  final VoidCallback onSignOut;

  const _AccountRow({
    required this.email,
    required this.displayName,
    required this.onSignOut,
  });

  String get _name {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final mail = email;
    if (mail == null || mail.isEmpty) return 'Account';
    final at = mail.indexOf('@');
    return at > 0 ? mail.substring(0, at) : mail;
  }

  String get _initial {
    final n = _name;
    return n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final email = this.email;
    return PopupMenuButton<String>(
      key: WebKeys.navAccountMenu,
      tooltip: 'Account',
      position: PopupMenuPosition.over,
      color: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      onSelected: (value) {
        if (value == 'signOut') onSignOut();
      },
      itemBuilder: (context) => [
        if (email != null)
          PopupMenuItem<String>(
            key: WebKeys.navAccountEmail,
            enabled: false,
            height: 36,
            child: Text(
              email,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        PopupMenuItem<String>(
          key: WebKeys.navSignOut,
          value: 'signOut',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.logout, size: 16, color: cs.onSurface),
              const SizedBox(width: 10),
              const Text('Sign out'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                _initial,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    'Sign out',
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
