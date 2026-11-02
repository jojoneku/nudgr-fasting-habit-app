/// Per-device settings for notification capture.
///
/// Notification access is granted per device, so these never sync: a second
/// phone starts with capture off and its own allowlist. Stored under the
/// user's key scope so two accounts on one phone keep separate lists.
class CaptureSettings {
  final bool enabled;

  /// Allowlisted packages. Only these ever leave the native listener.
  final Set<String> sources;

  /// Display label per package, kept so Settings can name a source whose app
  /// is no longer installed.
  final Map<String, String> sourceLabels;

  /// Default account per package ("GCash" → the GCash account).
  final Map<String, String> accountBySource;

  /// Account per masked card suffix ("1234" → the BPI credit card). Wins over
  /// [accountBySource] when the notification text carries the digits.
  final Map<String, String> accountByLast4;

  /// Per package, words the notification *title* must contain for the native
  /// listener to keep it. Gmail's title is the sender, so `{gmail: ['BPI']}`
  /// keeps bank mail and drops everything else before it is stored.
  final Map<String, List<String>> senderFilters;

  final DateTime? lastCaptureAt;
  final DateTime? lastDrainAt;

  const CaptureSettings({
    this.enabled = false,
    this.sources = const {},
    this.sourceLabels = const {},
    this.accountBySource = const {},
    this.accountByLast4 = const {},
    this.senderFilters = const {},
    this.lastCaptureAt,
    this.lastDrainAt,
  });

  String labelFor(String packageName) =>
      sourceLabels[packageName] ?? packageName;

  CaptureSettings copyWith({
    bool? enabled,
    Set<String>? sources,
    Map<String, String>? sourceLabels,
    Map<String, String>? accountBySource,
    Map<String, String>? accountByLast4,
    Map<String, List<String>>? senderFilters,
    DateTime? lastCaptureAt,
    DateTime? lastDrainAt,
  }) =>
      CaptureSettings(
        enabled: enabled ?? this.enabled,
        sources: sources ?? this.sources,
        sourceLabels: sourceLabels ?? this.sourceLabels,
        accountBySource: accountBySource ?? this.accountBySource,
        accountByLast4: accountByLast4 ?? this.accountByLast4,
        senderFilters: senderFilters ?? this.senderFilters,
        lastCaptureAt: lastCaptureAt ?? this.lastCaptureAt,
        lastDrainAt: lastDrainAt ?? this.lastDrainAt,
      );

  factory CaptureSettings.fromJson(Map<String, dynamic> json) =>
      CaptureSettings(
        enabled: json['enabled'] as bool? ?? false,
        sources: ((json['sources'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet(),
        sourceLabels: _stringMap(json['sourceLabels']),
        accountBySource: _stringMap(json['accountBySource']),
        accountByLast4: _stringMap(json['accountByLast4']),
        senderFilters: _stringListMap(json['senderFilters']),
        lastCaptureAt:
            DateTime.tryParse(json['lastCaptureAt'] as String? ?? ''),
        lastDrainAt: DateTime.tryParse(json['lastDrainAt'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'sources': sources.toList(),
        'sourceLabels': sourceLabels,
        'accountBySource': accountBySource,
        'accountByLast4': accountByLast4,
        'senderFilters': senderFilters,
        'lastCaptureAt': lastCaptureAt?.toIso8601String(),
        'lastDrainAt': lastDrainAt?.toIso8601String(),
      };

  static Map<String, List<String>> _stringListMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is List)
          e.key.toString(): (e.value as List).map((v) => v.toString()).toList(),
    };
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value != null) e.key.toString(): e.value.toString()
    };
  }
}
