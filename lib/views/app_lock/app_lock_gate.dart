import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../presenters/app_lock_presenter.dart';
import 'app_lock_exemption.dart';
import 'app_lock_screen.dart';
import 'pin_entry_flow.dart';

/// Mount through `MaterialApp.builder` so it sits above the root Navigator:
/// every route, dialog, and sheet is beneath it, and Back / `pop` cannot
/// dismiss it.
///
/// While gated, the app below stays alive (state, scroll position, an open
/// form) but cannot be touched, focused, or read by a screen reader.
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.presenter, required this.child});

  final AppLockPresenter presenter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      // The app subtree is passed through untouched so a lock/unlock never
      // rebuilds it — only the three flags below flip.
      child: AppLockExemption(runner: presenter.runExempt, child: child),
      builder: (context, app) => _GateStack(
        gated: presenter.isGated,
        cover: _coverFor(presenter),
        app: app!,
      ),
    );
  }

  static Widget? _coverFor(AppLockPresenter p) {
    if (p.showPinReset) {
      return PinEntryFlow(presenter: p, mode: PinFlowMode.reset);
    }
    if (p.showLockScreen) return AppLockScreen(presenter: p);
    if (p.isGated) return const _BlankCover();
    return null;
  }
}

class _GateStack extends StatelessWidget {
  const _GateStack(
      {required this.gated, required this.cover, required this.app});

  final bool gated;
  final Widget? cover;
  final Widget app;

  @override
  Widget build(BuildContext context) {
    final cover = this.cover;
    return Stack(
      children: [
        // Always the same three wrappers, so toggling never remounts the app.
        ExcludeFocus(
          excluding: gated,
          child: ExcludeSemantics(
            excluding: gated,
            child: IgnorePointer(ignoring: gated, child: app),
          ),
        ),
        // Android Back is held by AppLockBackGuard, not here: above the
        // Navigator there is no route for a PopScope to register with.
        if (cover != null)
          Positioned.fill(child: _BlockShortcuts(child: cover)),
      ],
    );
  }
}

/// Swallows app-level keyboard shortcuts (e.g. Escape-to-pop) while gated.
class _BlockShortcuts extends StatelessWidget {
  const _BlockShortcuts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DoNothingIntent(),
      },
      child: child,
    );
  }
}

/// Keeps Android Back (and the predictive back gesture) from popping the
/// routes under the gate.
///
/// [WidgetsBinding] asks observers in the order they were added, and
/// `WidgetsApp` adds its own (which pops the Navigator) when it is built. So
/// [attach] this from the app root's `initState`, before it builds
/// `MaterialApp`, to be asked first.
class AppLockBackGuard with WidgetsBindingObserver {
  AppLockBackGuard(this.presenter);

  final AppLockPresenter presenter;

  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  Future<bool> didPopRoute() async => presenter.isGated;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) =>
      presenter.isGated;
}

/// Shown before the lock state is known, so content never flashes on a cold
/// start.
class _BlankCover extends StatelessWidget {
  const _BlankCover();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
}
