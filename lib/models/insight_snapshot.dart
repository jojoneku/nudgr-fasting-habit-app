import '../utils/insight_hash.dart';

/// One domain's compact slice of the Insight Engine's snapshot (Plan 057) —
/// a handful of already-rounded, JSON-primitive markers plus a stable
/// content hash used to cheaply detect "did this domain change?" without
/// diffing the raw values.
class SnapshotSection {
  const SnapshotSection({required this.name, required this.markers});

  /// Domain name, e.g. `'fasting'`, `'nutrition'`, `'finance'`.
  final String name;

  /// Marker values — `int`, `double`, `bool`, `String`, or `null` only, so
  /// they hash deterministically and round-trip through JSON untouched.
  /// Markers with no backing data are omitted entirely rather than stored
  /// as `null`, so "missing" reads the same to a trigger whether the module
  /// hasn't loaded yet or simply has nothing to report.
  final Map<String, Object?> markers;

  /// Stable content hash of [markers] (see `insight_hash.dart`). Two
  /// sections with identical marker values always hash the same, so the
  /// caller can persist this as a baseline and skip regeneration entirely
  /// when nothing changed.
  String get hash => hashMarkers(markers);

  Map<String, dynamic> toJson() => {'name': name, 'markers': markers};

  factory SnapshotSection.fromJson(Map<String, dynamic> json) =>
      SnapshotSection(
        name: json['name'] as String,
        markers: Map<String, Object?>.from(json['markers'] as Map),
      );
}

/// Immutable, compact digest of the whole app's state — one [SnapshotSection]
/// per domain. Built by `InsightSnapshotBuilder` (lib/utils), fed to
/// `evaluateTriggers` (lib/utils/insight_triggers.dart), and phrased into an
/// `Insight` by `InsightsPresenter` (Phase 3). Deliberately carries only
/// aggregated markers — never raw entries, food names, or transaction
/// memos — so it stays small (well under 1 KB serialized) and safe to send
/// to a cloud LLM.
class InsightSnapshot {
  const InsightSnapshot({
    required this.fasting,
    required this.nutrition,
    required this.finance,
    required this.quests,
    required this.activity,
    required this.body,
    required this.rpg,
  });

  final SnapshotSection fasting;
  final SnapshotSection nutrition;
  final SnapshotSection finance;
  final SnapshotSection quests;
  final SnapshotSection activity;
  final SnapshotSection body;
  final SnapshotSection rpg;

  /// All sections in a fixed, stable order — lets callers iterate / hash /
  /// diff without hand-listing every field at each call site.
  List<SnapshotSection> get sections =>
      [fasting, nutrition, finance, quests, activity, body, rpg];

  /// Section name → content hash, ready to persist as the diff baseline.
  Map<String, String> get sectionHashes => {
        for (final s in sections) s.name: s.hash,
      };

  Map<String, dynamic> toJson() => {
        for (final s in sections) s.name: s.toJson(),
      };

  factory InsightSnapshot.fromJson(Map<String, dynamic> json) =>
      InsightSnapshot(
        fasting: SnapshotSection.fromJson(
            json['fasting'] as Map<String, dynamic>),
        nutrition: SnapshotSection.fromJson(
            json['nutrition'] as Map<String, dynamic>),
        finance: SnapshotSection.fromJson(
            json['finance'] as Map<String, dynamic>),
        quests:
            SnapshotSection.fromJson(json['quests'] as Map<String, dynamic>),
        activity: SnapshotSection.fromJson(
            json['activity'] as Map<String, dynamic>),
        body: SnapshotSection.fromJson(json['body'] as Map<String, dynamic>),
        rpg: SnapshotSection.fromJson(json['rpg'] as Map<String, dynamic>),
      );

  /// Compact, human-readable text block (one line per domain, so ≤ ~10
  /// lines in practice) for the LLM prompt. Sections named in
  /// [changedSections] are marked `[NEW]` so the model can focus on what
  /// actually moved instead of re-reading the whole digest every time.
  String toPromptDigest({Set<String> changedSections = const {}}) {
    final buffer = StringBuffer();
    for (final s in sections) {
      final tag = changedSections.contains(s.name) ? ' [NEW]' : '';
      buffer.writeln('${_titleCase(s.name)}$tag: ${_markersLine(s.markers)}');
    }
    return buffer.toString().trimRight();
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _markersLine(Map<String, Object?> markers) {
    final sortedKeys = markers.keys.toList()..sort();
    final rendered = sortedKeys
        .where((k) => markers[k] != null)
        .map((k) => '$k=${markers[k]}');
    return rendered.isEmpty ? '(no data)' : rendered.join(', ');
  }
}
