import 'package:flutter/foundation.dart';

/// Mixin for ChangeNotifier subclasses that perform async work.
///
/// Guards every notifyListeners() call with a disposed check so that
/// dismissing a screen while an async operation is in-flight does not
/// crash with "A ChangeNotifier was used after being disposed."
///
/// Usage:
///   class MyPresenter extends ChangeNotifier with SafeNotifier { ... }
///
/// Replace post-await notifyListeners() calls with safeNotify().
/// Synchronous calls may also use safeNotify() for consistency.
mixin SafeNotifier on ChangeNotifier {
  bool _disposed = false;

  /// True after [dispose] has been called. Subclasses in other libraries must
  /// use this getter rather than accessing [_disposed] directly (Dart privacy
  /// is library-scoped, not class-scoped).
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
