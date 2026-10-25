import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PIN dots plus a 3×4 keypad. Shared by the lock screen and the set-PIN flow.
///
/// Lives under the app-lock gate, which sits above the root Navigator — so no
/// tooltips, dialogs, or snack bars here (they need an Overlay/Navigator).
/// Accepts physical digit keys and Backspace when [acceptsKeyboard] is set.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.length,
    required this.onCompleted,
    this.enabled = true,
    this.wrongSignal = 0,
    this.onBiometric,
    this.acceptsKeyboard = true,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final bool enabled;

  /// Change it to shake and clear the dots (a wrong PIN).
  final int wrongSignal;

  /// Shows the biometric key when non-null.
  final VoidCallback? onBiometric;
  final bool acceptsKeyboard;

  static const double keySize = 72;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  final StringBuffer _digits = StringBuffer();
  final FocusNode _focus = FocusNode(debugLabel: 'PinPad');
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  @override
  void didUpdateWidget(PinPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wrongSignal != oldWidget.wrongSignal) {
      _clear();
      _shake.forward(from: 0);
      HapticFeedback.heavyImpact();
    }
    if (widget.length != oldWidget.length) _clear();
  }

  @override
  void dispose() {
    _shake.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _clear() => setState(_digits.clear);

  void _add(String digit) {
    if (!widget.enabled || _digits.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _digits.write(digit));
    if (_digits.length == widget.length) {
      final pin = _digits.toString();
      // Clear now: the parent decides what happens next (unlock, confirm
      // step, or a wrong-PIN shake) and the dots must not keep the digits.
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _clear();
        widget.onCompleted(pin);
      });
    }
  }

  void _backspace() {
    if (!widget.enabled || _digits.isEmpty) return;
    final current = _digits.toString();
    setState(() {
      _digits
        ..clear()
        ..write(current.substring(0, current.length - 1));
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.acceptsKeyboard || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final char = event.character;
    if (char != null && char.length == 1 && '0123456789'.contains(char)) {
      _add(char);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) => Transform.translate(
              offset: Offset(math.sin(_shake.value * math.pi * 4) * 10, 0),
              child: child,
            ),
            child: _PinDots(length: widget.length, filled: _digits.length),
          ),
          const SizedBox(height: 32),
          _Keypad(
            enabled: widget.enabled,
            onDigit: _add,
            onBackspace: _backspace,
            onBiometric: widget.onBiometric,
          ),
        ],
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.filled});

  final int length;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$filled of $length digits entered',
      liveRegion: true,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? scheme.primary : Colors.transparent,
                border: Border.all(
                  color: i < filled ? scheme.primary : scheme.outline,
                  width: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    final biometric = onBiometric;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in row) _DigitKey(digit: d, onTap: onDigit),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              biometric == null
                  ? const SizedBox.square(dimension: PinPad.keySize + 16)
                  : _IconKey(
                      icon: Icons.fingerprint,
                      label: 'Unlock with biometrics',
                      onTap: biometric,
                    ),
              _DigitKey(digit: '0', onTap: onDigit),
              _IconKey(
                icon: Icons.backspace_outlined,
                label: 'Delete digit',
                onTap: onBackspace,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey({required this.digit, required this.onTap});

  final String digit;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _KeyShell(
      label: digit,
      filled: true,
      onTap: () => onTap(digit),
      child: Text(
        digit,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _IconKey extends StatelessWidget {
  const _IconKey({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _KeyShell(
      label: label,
      filled: false,
      onTap: onTap,
      child: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _KeyShell extends StatelessWidget {
  const _KeyShell({
    required this.label,
    required this.filled,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: filled ? scheme.surfaceContainerHigh : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: PinPad.keySize,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
