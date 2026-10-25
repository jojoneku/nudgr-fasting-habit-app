import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../presenters/app_lock_presenter.dart';

/// Web: feeds pointer, wheel, touch, and key input to the app lock's idle
/// clock. Translucent — it never consumes an event.
class AppLockActivityDetector extends StatefulWidget {
  const AppLockActivityDetector({
    super.key,
    required this.presenter,
    required this.child,
  });

  final AppLockPresenter presenter;
  final Widget child;

  @override
  State<AppLockActivityDetector> createState() =>
      _AppLockActivityDetectorState();
}

class _AppLockActivityDetectorState extends State<AppLockActivityDetector> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    widget.presenter.recordActivity();
    return false; // observe only
  }

  void _onPointer(PointerEvent _) => widget.presenter.recordActivity();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerHover: _onPointer,
      onPointerSignal: _onPointer,
      child: widget.child,
    );
  }
}
