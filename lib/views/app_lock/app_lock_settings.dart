import 'package:flutter/material.dart';

import '../../presenters/app_lock_presenter.dart';
import '../widgets/system/system.dart';
import 'pin_entry_flow.dart';

/// The Security rows: App lock, Lock after, biometrics, Change PIN, Lock now.
///
/// One widget for every surface — mobile Settings, the narrow-web More page,
/// and the desktop-web sidebar dialog — so the platforms cannot drift. The
/// biometric row only exists where [AppLockPresenter.supportsBiometrics].
class AppLockSettingsTiles extends StatelessWidget {
  const AppLockSettingsTiles({super.key, required this.presenter});

  final AppLockPresenter presenter;

  /// Footer copy for the section that hosts these tiles.
  static const String footer =
      'Your PIN works on all your devices. "Lock after" and biometrics apply '
      'to this device only.';

  Future<void> _toggle(BuildContext context, bool on) async {
    final ok = await PinEntryFlow.push(
      context,
      presenter: presenter,
      mode: on ? PinFlowMode.create : PinFlowMode.disable,
    );
    if (ok && context.mounted) {
      AppToast.success(context, on ? 'App lock is on' : 'App lock is off');
    }
  }

  Future<void> _changePin(BuildContext context) async {
    final ok = await PinEntryFlow.push(
      context,
      presenter: presenter,
      mode: PinFlowMode.change,
    );
    if (ok && context.mounted) AppToast.success(context, 'PIN changed');
  }

  Future<void> _setBiometrics(BuildContext context, bool on) async {
    final ok = await presenter.setBiometricsEnabled(on);
    if (!ok && on && context.mounted) {
      AppToast.error(context, 'Biometrics could not be confirmed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (!presenter.isSignedIn) return const _SignInHint();
        if (!presenter.isAvailable) return const _UnavailableHint();
        final cs = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              value: presenter.isEnabled,
              onChanged: (on) => _toggle(context, on),
              secondary: Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
              title: const Text('App lock'),
              subtitle: const Text('Ask for your PIN to open the app'),
            ),
            if (presenter.isEnabled) ...[
              ListTile(
                minTileHeight: 56,
                leading: Icon(Icons.timer_outlined, color: cs.onSurfaceVariant),
                title: const Text('Lock after'),
                trailing: DropdownButton<Duration>(
                  value: presenter.lockAfter,
                  underline: const SizedBox.shrink(),
                  onChanged: (d) {
                    if (d != null) presenter.setLockAfter(d);
                  },
                  items: [
                    for (final d in presenter.lockAfterOptions)
                      DropdownMenuItem(
                        value: d,
                        child: Text(presenter.labelForLockAfter(d)),
                      ),
                  ],
                ),
              ),
              if (presenter.biometricsAvailable)
                SwitchListTile(
                  value: presenter.biometricsEnabled,
                  onChanged: (on) => _setBiometrics(context, on),
                  secondary:
                      Icon(Icons.fingerprint, color: cs.onSurfaceVariant),
                  title: const Text('Use fingerprint or face'),
                  subtitle: const Text('Your PIN still works as a backup'),
                ),
              ListTile(
                minTileHeight: 56,
                leading: Icon(Icons.pin_outlined, color: cs.onSurfaceVariant),
                title: const Text('Change PIN'),
                trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                onTap: () => _changePin(context),
              ),
              ListTile(
                minTileHeight: 56,
                leading:
                    Icon(Icons.lock_clock_outlined, color: cs.onSurfaceVariant),
                title: const Text('Lock now'),
                onTap: presenter.lockNow,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SignInHint extends StatelessWidget {
  const _SignInHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 56,
      leading: Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
      title: const Text('App lock'),
      subtitle: const Text('Sign in to use app lock'),
    );
  }
}

class _UnavailableHint extends StatelessWidget {
  const _UnavailableHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 56,
      leading: Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
      title: const Text('App lock'),
      subtitle: const Text(AppLockPresenter.unavailableMessage),
    );
  }
}

/// Desktop-web sidebar: "Security" opens the tiles in a dialog, and a lock
/// button locks at once while the app lock is on.
class AppLockSidebarActions extends StatelessWidget {
  const AppLockSidebarActions({super.key, required this.presenter});

  final AppLockPresenter presenter;

  void _openSecurity(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Security'),
        contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppLockSettingsTiles(presenter: presenter),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  AppLockSettingsTiles.footer,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => _openSecurity(context),
              icon: const Icon(Icons.shield_outlined, size: 16),
              label: const Text('Security'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size(44, 44),
              ),
            ),
          ),
          if (presenter.isEnabled)
            IconButton(
              tooltip: 'Lock now',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: presenter.lockNow,
              icon: Icon(Icons.lock_outline,
                  size: 18, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
