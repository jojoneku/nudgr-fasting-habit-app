import 'package:flutter/widgets.dart';

typedef ExemptRunner = Future<T> Function<T>(Future<T> Function() action);

/// Lets a widget that sends the app to the background on the user's behalf —
/// the photo picker, the camera — do so without tripping the app lock.
///
/// [AppLockGate] provides it above the Navigator, so every route and sheet
/// can reach it. It carries only the exemption hook, never the presenter:
/// views still get their presenters by constructor injection (rule 6). This
/// exists so a picker three sheets deep does not need the lock threaded
/// through every constructor between it and the app root.
class AppLockExemption extends InheritedWidget {
  const AppLockExemption({
    super.key,
    required this.runner,
    required super.child,
  });

  final ExemptRunner runner;

  /// Runs [action] exempt from the app lock. Without a gate above (tests,
  /// previews) it just runs [action].
  static Future<T> run<T>(BuildContext context, Future<T> Function() action) {
    final scope = context.getInheritedWidgetOfExactType<AppLockExemption>();
    return scope == null ? action() : scope.runner<T>(action);
  }

  @override
  bool updateShouldNotify(AppLockExemption oldWidget) =>
      runner != oldWidget.runner;
}
