import 'package:flutter/material.dart';

import '../../presenters/app_lock_presenter.dart';
import 'app_lock_screen.dart';
import 'pin_pad.dart';

enum PinFlowMode {
  /// Settings → App lock on: choose → confirm.
  create,

  /// Mandatory gate after Forgot PIN: choose → confirm, or turn the lock off.
  reset,

  /// Settings → Change PIN: current → choose → confirm.
  change,

  /// Settings → App lock off: current.
  disable,
}

enum _Step { current, choose, confirm }

/// The multi-step PIN entry used by Settings (as a route) and by the reset
/// gate (inline, above the Navigator). The account write happens in the
/// presenter; this widget only sequences the steps.
class PinEntryFlow extends StatefulWidget {
  const PinEntryFlow({
    super.key,
    required this.presenter,
    required this.mode,
    this.onDone,
  });

  final AppLockPresenter presenter;
  final PinFlowMode mode;

  /// Called with true once the change landed on the account.
  final ValueChanged<bool>? onDone;

  /// Pushes the flow as a full-screen route; resolves to true on success.
  static Future<bool> push(
    BuildContext context, {
    required AppLockPresenter presenter,
    required PinFlowMode mode,
  }) async {
    presenter.clearError();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(routeContext).pop(false),
            ),
          ),
          body: PinEntryFlow(
            presenter: presenter,
            mode: mode,
            onDone: (ok) => Navigator.of(routeContext).pop(ok),
          ),
        ),
      ),
    );
    return result ?? false;
  }

  @override
  State<PinEntryFlow> createState() => _PinEntryFlowState();
}

class _PinEntryFlowState extends State<PinEntryFlow> {
  late _Step _step = _firstStep(widget.mode);
  late int _length = widget.presenter.pinLength;
  String? _currentPin;
  String? _firstEntry;
  String? _retryPin;
  String? _localError;
  int _mismatchSignal = 0;

  static _Step _firstStep(PinFlowMode mode) =>
      mode == PinFlowMode.change || mode == PinFlowMode.disable
          ? _Step.current
          : _Step.choose;

  String get _title => switch (_step) {
        _Step.current => 'Enter your current PIN',
        _Step.choose when widget.mode == PinFlowMode.change =>
          'Choose a new PIN',
        _Step.choose => 'Choose a PIN',
        _Step.confirm => 'Enter the PIN again',
      };

  String? get _subtitle => switch ((_step, widget.mode)) {
        (_Step.choose, PinFlowMode.reset) =>
          'Set a new PIN. It replaces the old one on all your devices.',
        (_Step.choose, _) => 'This PIN unlocks the app on all your devices.',
        (_Step.current, PinFlowMode.disable) =>
          'This turns off the app lock on all your devices.',
        _ => null,
      };

  /// The keypad length: the existing PIN's while checking it, the chosen one
  /// while setting a new one.
  int get _padLength =>
      _step == _Step.current ? widget.presenter.pinLength : _length;

  Future<void> _onCompleted(String pin) async {
    setState(() {
      _localError = null;
      _retryPin = null;
    });
    widget.presenter.clearError();
    switch (_step) {
      case _Step.current:
        await _onCurrent(pin);
      case _Step.choose:
        setState(() {
          _firstEntry = pin;
          _step = _Step.confirm;
        });
      case _Step.confirm:
        await _onConfirm(pin);
    }
  }

  Future<void> _onCurrent(String pin) async {
    final presenter = widget.presenter;
    if (widget.mode == PinFlowMode.disable) {
      if (await presenter.disable(pin)) widget.onDone?.call(true);
      return;
    }
    if (await presenter.verifyCurrentPin(pin)) {
      setState(() {
        _currentPin = pin;
        _step = _Step.choose;
      });
    }
  }

  Future<void> _onConfirm(String pin) async {
    if (pin != _firstEntry) {
      setState(() {
        _localError = 'PINs do not match. Try again.';
        _mismatchSignal++;
        _firstEntry = null;
        _step = _Step.choose;
      });
      return;
    }
    await _submit(pin);
  }

  Future<void> _submit(String pin) async {
    final presenter = widget.presenter;
    final current = _currentPin;
    final ok = widget.mode == PinFlowMode.change && current != null
        ? await presenter.changePin(current, pin)
        : await presenter.setNewPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onDone?.call(true);
    } else {
      setState(() => _retryPin = pin);
    }
  }

  void _setLength(Set<int> selection) {
    setState(() {
      _length = selection.first;
      _firstEntry = null;
      _step = _Step.choose;
    });
  }

  Future<void> _turnOff() async {
    if (await widget.presenter.disableDuringReset()) {
      widget.onDone?.call(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: widget.presenter,
          builder: (context, _) {
            final p = widget.presenter;
            return LockLayout(
              header: LockHeader(
                title: _title,
                subtitle: _subtitle,
                message: _localError ?? p.statusMessage,
              ),
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LengthChoice(
                    visible: _step == _Step.choose,
                    length: _length,
                    onChanged: _setLength,
                  ),
                  _Busy(busy: p.isBusy),
                  PinPad(
                    // A new key per step resets the dots between steps.
                    key: ValueKey(_step),
                    length: _padLength,
                    enabled: p.keypadEnabled,
                    wrongSignal: p.wrongPinSignal + _mismatchSignal,
                    onCompleted: _onCompleted,
                  ),
                ],
              ),
              footer: _Footer(
                retryVisible: _retryPin != null,
                onRetry: () => _submit(_retryPin!),
                turnOffVisible:
                    widget.mode == PinFlowMode.reset && p.canTurnOffWithoutPin,
                onTurnOff: _turnOff,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LengthChoice extends StatelessWidget {
  const _LengthChoice({
    required this.visible,
    required this.length,
    required this.onChanged,
  });

  final bool visible;
  final int length;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(height: 48 + 24);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 4, label: Text('4 digits')),
          ButtonSegment(value: 6, label: Text('6 digits')),
        ],
        selected: {length},
        showSelectedIcon: false,
        onSelectionChanged: onChanged,
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: busy ? const LinearProgressIndicator() : null,
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.retryVisible,
    required this.onRetry,
    required this.turnOffVisible,
    required this.onTurnOff,
  });

  final bool retryVisible;
  final VoidCallback onRetry;
  final bool turnOffVisible;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (retryVisible)
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            child: const Text('Try again'),
          ),
        if (turnOffVisible)
          TextButton(
            onPressed: onTurnOff,
            style: TextButton.styleFrom(minimumSize: const Size(44, 48)),
            child: const Text('Turn off app lock'),
          ),
        if (!retryVisible && !turnOffVisible) const SizedBox(height: 48),
      ],
    );
  }
}
