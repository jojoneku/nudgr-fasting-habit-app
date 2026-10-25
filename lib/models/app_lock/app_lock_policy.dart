/// The per-platform rules of the app lock. The presenter takes one of these
/// instead of branching on `kIsWeb`.
class AppLockPolicy {
  /// The "Lock after" choices, in the order Settings shows them.
  final List<Duration> lockAfterOptions;
  final Duration defaultLockAfter;

  /// Web locks on idle input (and hidden-tab time); mobile locks on time spent
  /// in the background, because the screen timeout already backgrounds it.
  final bool tracksIdleInput;

  /// Mobile locks on every cold start. Web only locks on reload when the idle
  /// time already passed — a reload mid-session is not leaving the app.
  final bool lockOnEveryColdStart;

  /// Wrong PINs in a row before a forced sign-out into the Forgot PIN path.
  /// Null means never (mobile: sign-out is not a safe escape hatch there).
  final int? forcedSignOutAttempts;

  const AppLockPolicy({
    required this.lockAfterOptions,
    required this.defaultLockAfter,
    required this.tracksIdleInput,
    required this.lockOnEveryColdStart,
    required this.forcedSignOutAttempts,
  });

  /// Wrong PINs in a row before the first cooldown.
  static const int attemptsBeforeCooldown = 5;
  static const Duration firstCooldown = Duration(seconds: 30);
  static const Duration maxCooldown = Duration(minutes: 15);

  static const AppLockPolicy mobile = AppLockPolicy(
    lockAfterOptions: [
      Duration.zero,
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ],
    defaultLockAfter: Duration(minutes: 1),
    tracksIdleInput: false,
    lockOnEveryColdStart: true,
    forcedSignOutAttempts: null,
  );

  static const AppLockPolicy web = AppLockPolicy(
    lockAfterOptions: [
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 60),
    ],
    defaultLockAfter: Duration(minutes: 5),
    tracksIdleInput: true,
    lockOnEveryColdStart: false,
    forcedSignOutAttempts: 10,
  );

  /// The cooldown after the [failedAttempts]-th wrong PIN in a row, or null
  /// when none applies yet: 30 s at 5, doubling per extra miss, capped.
  static Duration? cooldownFor(int failedAttempts) {
    if (failedAttempts < attemptsBeforeCooldown) return null;
    final doublings = failedAttempts - attemptsBeforeCooldown;
    if (doublings >= 5) return maxCooldown; // 30 s × 2^5 already exceeds 15 min
    final cooldown = firstCooldown * (1 << doublings);
    return cooldown > maxCooldown ? maxCooldown : cooldown;
  }
}
