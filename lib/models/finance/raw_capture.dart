/// One notification as the native listener queued it, before parsing.
///
/// This is the shape that crosses the `com.nudgr.app/capture` channel. It
/// carries nothing the parser does not need: the posting app, when it posted,
/// the title and body text, and a fingerprint the native side already used to
/// drop duplicates. See `.claude/plans/070-capture-inbox.md` §5.
class RawCapture {
  final String packageName;
  final String appLabel;
  final DateTime postedAt;
  final String title;
  final String text;
  final String fingerprint;

  const RawCapture({
    required this.packageName,
    required this.appLabel,
    required this.postedAt,
    required this.title,
    required this.text,
    required this.fingerprint,
  });

  factory RawCapture.fromMap(Map<Object?, Object?> m) => RawCapture(
        packageName: m['pkg'] as String? ?? '',
        appLabel: m['label'] as String? ?? '',
        postedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['postTime'] as num?)?.toInt() ?? 0),
        title: m['title'] as String? ?? '',
        text: m['text'] as String? ?? '',
        fingerprint: m['fp'] as String? ?? '',
      );

  Map<String, Object?> toMap() => {
        'pkg': packageName,
        'label': appLabel,
        'postTime': postedAt.millisecondsSinceEpoch,
        'title': title,
        'text': text,
        'fp': fingerprint,
      };
}

/// An app the listener has seen post a notification recently. Label and
/// package only — the native side keeps no text for apps outside the
/// allowlist. Shown in Settings so the user can add a source by name.
class RecentApp {
  final String packageName;
  final String appLabel;
  final DateTime lastSeen;

  const RecentApp({
    required this.packageName,
    required this.appLabel,
    required this.lastSeen,
  });

  factory RecentApp.fromMap(Map<Object?, Object?> m) => RecentApp(
        packageName: m['pkg'] as String? ?? '',
        appLabel: m['label'] as String? ?? '',
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
            (m['lastSeen'] as num?)?.toInt() ?? 0),
      );
}
