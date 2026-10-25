import 'package:flutter/material.dart';

import '../../presenters/app_lock_presenter.dart';
import 'pin_pad.dart';

/// The opaque lock screen. Rendered by [AppLockGate] above the root Navigator,
/// so it confirms Forgot PIN inline instead of with a dialog.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, required this.presenter});

  final AppLockPresenter presenter;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _confirmingForgot = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.presenter.maybeAutoPromptBiometrics();
    });
  }

  void _onForgotTapped() {
    widget.presenter.clearError();
    if (widget.presenter.forgotPinSignsOut) {
      setState(() => _confirmingForgot = true);
    } else {
      widget.presenter.forgotPin();
    }
  }

  void _cancelForgot() => setState(() => _confirmingForgot = false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: widget.presenter,
          builder: (context, _) {
            final p = widget.presenter;
            return LockLayout(
              header: LockHeader(title: 'Enter PIN', message: p.statusMessage),
              body: _confirmingForgot
                  ? _ForgotConfirm(
                      onConfirm: () => p.forgotPin(),
                      onCancel: _cancelForgot,
                    )
                  : PinPad(
                      length: p.pinLength,
                      enabled: p.keypadEnabled,
                      wrongSignal: p.wrongPinSignal,
                      onCompleted: p.submitPin,
                      onBiometric:
                          p.biometricsEnabled ? p.unlockWithBiometrics : null,
                    ),
              footer: _confirmingForgot
                  ? null
                  : TextButton(
                      onPressed: _onForgotTapped,
                      style:
                          TextButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: const Text('Forgot PIN?'),
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Centered on wide screens (max 360 px); the keypad sits low on phones.
class LockLayout extends StatelessWidget {
  const LockLayout(
      {super.key, required this.header, required this.body, this.footer});

  final Widget header;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header,
                    const SizedBox(height: 40),
                    body,
                    const SizedBox(height: 16),
                    footer ?? const SizedBox(height: 44),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title plus a fixed-height status line, so the keypad does not jump when a
/// message appears. Shared with [PinEntryFlow].
class LockHeader extends StatelessWidget {
  const LockHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.message,
  });

  final String title;

  /// Neutral guidance, shown when there is no [message].
  final String? subtitle;

  /// An error or status (shown in the error color).
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.lock_outline, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: message != null
              ? Text(
                  message!,
                  textAlign: TextAlign.center,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                )
              : Text(
                  subtitle ?? '',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
        ),
      ],
    );
  }
}

class _ForgotConfirm extends StatelessWidget {
  const _ForgotConfirm({required this.onConfirm, required this.onCancel});

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'You will be signed out. Sign in again with Google, then set a new '
          'PIN. The new PIN works on all your devices.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onConfirm,
          style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
          child: const Text('Sign out and reset PIN'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(minimumSize: const Size(44, 48)),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
