import 'dart:convert';

/// The app-lock state that belongs to this device only and never syncs.
///
/// The PIN itself is account-level ([PinVerifier]); the timeout, the biometric
/// switch, and the wrong-PIN throttle are per device, because a laptop and a
/// phone want different timeouts and a borrower can only reach one device.
class AppLockDeviceState {
  /// Null means "use the platform default" from [AppLockPolicy].
  final int? lockAfterSeconds;
  final bool biometricsEnabled;
  final int failedAttempts;
  final DateTime? cooldownUntil;

  /// Web only: the last pointer/key input, so a reload can tell whether the
  /// idle time already passed.
  final DateTime? lastActivityAt;

  /// Set by the web Forgot PIN path before it signs out. The next fresh
  /// sign-in on this device must set a new PIN before any content shows.
  final bool pinResetPending;

  const AppLockDeviceState({
    this.lockAfterSeconds,
    this.biometricsEnabled = false,
    this.failedAttempts = 0,
    this.cooldownUntil,
    this.lastActivityAt,
    this.pinResetPending = false,
  });

  AppLockDeviceState copyWith({
    int? lockAfterSeconds,
    bool? biometricsEnabled,
    int? failedAttempts,
    DateTime? cooldownUntil,
    bool clearCooldown = false,
    DateTime? lastActivityAt,
    bool? pinResetPending,
  }) {
    return AppLockDeviceState(
      lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      cooldownUntil:
          clearCooldown ? null : (cooldownUntil ?? this.cooldownUntil),
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      pinResetPending: pinResetPending ?? this.pinResetPending,
    );
  }

  /// Clears the wrong-PIN throttle. Used on a correct unlock and on sign-out.
  AppLockDeviceState withThrottleReset() =>
      copyWith(failedAttempts: 0, clearCooldown: true);

  Map<String, dynamic> toJson() => {
        if (lockAfterSeconds != null) 'lockAfterSeconds': lockAfterSeconds,
        'biometricsEnabled': biometricsEnabled,
        'failedAttempts': failedAttempts,
        if (cooldownUntil != null)
          'cooldownUntil': cooldownUntil!.toUtc().toIso8601String(),
        if (lastActivityAt != null)
          'lastActivityAt': lastActivityAt!.toUtc().toIso8601String(),
        'pinResetPending': pinResetPending,
      };

  factory AppLockDeviceState.fromJson(Map<String, dynamic> json) {
    return AppLockDeviceState(
      lockAfterSeconds: json['lockAfterSeconds'] as int?,
      biometricsEnabled: json['biometricsEnabled'] as bool? ?? false,
      failedAttempts: json['failedAttempts'] as int? ?? 0,
      cooldownUntil: _parseDate(json['cooldownUntil']),
      lastActivityAt: _parseDate(json['lastActivityAt']),
      pinResetPending: json['pinResetPending'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  /// Falls back to the defaults for a missing or unreadable blob.
  factory AppLockDeviceState.decode(String? source) {
    if (source == null || source.isEmpty) return const AppLockDeviceState();
    try {
      final json = jsonDecode(source);
      if (json is Map<String, dynamic>) {
        return AppLockDeviceState.fromJson(json);
      }
    } on FormatException {
      // fall through to defaults
    } on TypeError {
      // a field of the wrong type — fall through to defaults
    }
    return const AppLockDeviceState();
  }

  static DateTime? _parseDate(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
}
