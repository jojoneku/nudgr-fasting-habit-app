import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/insight.dart';
import 'package:intermittent_fasting/presenters/insights_presenter.dart';
import 'package:intermittent_fasting/utils/insight_snapshot_builder.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Test double that lets us drive the whole refresh / brief / tier flow
/// against a controlled snapshot: [buildSnapshotInputs] is overridden so no
/// real feature presenters are needed, and [refresh] is counted so the
/// debounce coalescing can be asserted.
class _TestInsightsPresenter extends InsightsPresenter {
  _TestInsightsPresenter({
    required super.storage,
    required super.fasting,
    required super.stats,
    required super.quests,
    super.onDeviceAi,
    super.cloudAi,
    super.clock,
  });

  InsightSnapshotInputs inputs = const InsightSnapshotInputs();
  int refreshCalls = 0;

  @override
  InsightSnapshotInputs buildSnapshotInputs() => inputs;

  @override
  Future<void> refresh() async {
    refreshCalls++;
    await super.refresh();
  }
}

void main() {
  late MockStorageService storage;
  late MockFastingPresenter fasting;
  late MockStatsPresenter stats;
  late MockQuestPresenter quests;

  // Closure-backed in-memory persistence — mockito NiceMock stubs read/write
  // these, giving a stateful fake without hand-rolling all of StorageService.
  Map<String, String>? baseline;
  List<Insight> insights = [];
  Map<String, DateTime>? cooldowns;
  DateTime? briefDate;

  DateTime now = DateTime(2026, 7, 12, 21, 0);
  DateTime clock() => now;

  setUp(() {
    baseline = null;
    insights = [];
    cooldowns = null;
    briefDate = null;
    now = DateTime(2026, 7, 12, 21, 0);

    storage = MockStorageService();
    fasting = MockFastingPresenter();
    stats = MockStatsPresenter();
    quests = MockQuestPresenter();

    when(storage.loadInsights()).thenAnswer((_) async => List.of(insights));
    when(storage.saveInsights(any)).thenAnswer((inv) async {
      insights = List.of(inv.positionalArguments[0] as List<Insight>);
    });
    when(storage.loadInsightBaselineHashes())
        .thenAnswer((_) async => baseline == null ? null : Map.of(baseline!));
    when(storage.saveInsightBaselineHashes(any)).thenAnswer((inv) async {
      baseline = Map.of(inv.positionalArguments[0] as Map<String, String>);
    });
    when(storage.loadInsightCooldowns())
        .thenAnswer((_) async => cooldowns == null ? null : Map.of(cooldowns!));
    when(storage.saveInsightCooldowns(any)).thenAnswer((inv) async {
      cooldowns = Map.of(inv.positionalArguments[0] as Map<String, DateTime>);
    });
    when(storage.loadLastDailyBriefDate()).thenAnswer((_) async => briefDate);
    when(storage.saveLastDailyBriefDate(any)).thenAnswer((inv) async {
      briefDate = inv.positionalArguments[0] as DateTime;
    });
  });

  _TestInsightsPresenter build({
    MockAiCoachService? onDeviceAi,
    MockAiCoachService? cloudAi,
  }) =>
      _TestInsightsPresenter(
        storage: storage,
        fasting: fasting,
        stats: stats,
        quests: quests,
        onDeviceAi: onDeviceAi,
        cloudAi: cloudAi,
        clock: clock,
      );

  // A benign snapshot that fires no triggers.
  const benign = InsightSnapshotInputs(level: 5, xp: 10, hp: 100);
  // Fires exactly finance.billImminent (urgent).
  const billInputs = InsightSnapshotInputs(billImminent: true, level: 5);

  MockAiCoachService availableAi(Stream<String> Function() answer) {
    final ai = MockAiCoachService();
    when(ai.isAvailable).thenReturn(true);
    when(ai.respond(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
    )).thenAnswer((_) => answer());
    return ai;
  }

  int nudgeCount(InsightsPresenter p) =>
      p.recent.where((i) => i.kind == InsightKind.nudge).length;

  group('hash gate', () {
    test('unchanged hashes → no eval, no writes, no service calls', () async {
      final ai = availableAi(() => Stream.fromIterable(['x']));
      final p = build(onDeviceAi: ai);
      p.inputs = benign;
      await p.init();
      await p.refresh(); // first refresh sets baseline (nothing fires)

      clearInteractions(storage);
      await p.refresh(); // identical snapshot → must short-circuit

      verifyNever(storage.saveInsightBaselineHashes(any));
      verifyNever(storage.saveInsights(any));
      verifyNever(storage.saveInsightCooldowns(any));
      verifyNever(ai.respond(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
      ));
      expect(p.recent, isEmpty);
      p.dispose();
    });

    test('changed section → trigger fires, insight + baseline persisted',
        () async {
      final p = build();
      p.inputs = billInputs; // fires finance.billImminent
      await p.init();
      await p.refresh();

      expect(nudgeCount(p), 1);
      expect(p.recent.first.triggerId, 'finance.billImminent');
      expect(p.recent.first.source, InsightSource.rules); // no AI wired
      expect(insights.length, 1); // persisted
      expect(baseline, isNotNull); // baseline persisted
      expect(cooldowns!['finance.billImminent'], isNotNull);
      p.dispose();
    });
  });

  group('cooldowns', () {
    test('suppresses a repeat fire within the window, re-fires after expiry',
        () async {
      final p = build();
      p.inputs = billInputs;
      await p.init();
      await p.refresh();
      expect(nudgeCount(p), 1);

      // Change an unrelated marker so the hash gate opens, keep bill imminent.
      p.inputs = const InsightSnapshotInputs(billImminent: true, level: 6);
      await p.refresh();
      expect(nudgeCount(p), 1, reason: 'still in 1-day cooldown');

      // Advance beyond the 1-day cooldown and open the gate again.
      now = now.add(const Duration(days: 2));
      p.inputs = const InsightSnapshotInputs(billImminent: true, level: 7);
      await p.refresh();
      expect(nudgeCount(p), 2, reason: 'cooldown elapsed → re-fires');
      p.dispose();
    });
  });

  group('daily surface cap', () {
    test('at most 2 nudges/day even when 3 triggers fire', () async {
      final p = build();
      // billImminent + categoryBlown + overGoal all fire (all urgent).
      p.inputs = const InsightSnapshotInputs(
        billImminent: true,
        anyCategoryOverBudget: true,
        todayCalories: 5000,
        effectiveGoal: 2000,
      );
      await p.init();
      await p.refresh();

      expect(nudgeCount(p), 2);
      // Only the two surfaced triggers got a cooldown stamp.
      expect(
        cooldowns!.keys.where((k) => !k.startsWith('_')).length,
        2,
      );
      p.dispose();
    });
  });

  group('daily brief', () {
    test(
        'generates once/day; second call same day no-ops; next day regenerates',
        () async {
      final p = build();
      p.inputs = benign;
      await p.init();

      await p.generateDailyBriefIfDue();
      expect(p.dailyBrief, isNotNull);
      expect(p.dailyBrief!.source, InsightSource.rules);
      expect(briefDate, isNotNull);
      final briefsDay1 =
          p.recent.where((i) => i.kind == InsightKind.dailyBrief).length;
      expect(briefsDay1, 1);

      await p.generateDailyBriefIfDue(); // same day → no-op
      expect(
        p.recent.where((i) => i.kind == InsightKind.dailyBrief).length,
        1,
      );

      now = now.add(const Duration(days: 1));
      await p.generateDailyBriefIfDue();
      expect(
        p.recent.where((i) => i.kind == InsightKind.dailyBrief).length,
        2,
      );
      p.dispose();
    });
  });

  group('tier routing', () {
    test('on-device unavailable + cloud unavailable → rules fallback',
        () async {
      final p = build(); // no AI wired
      p.inputs = billInputs;
      await p.init();
      await p.refresh();
      expect(p.current!.source, InsightSource.rules);
      expect(p.current!.text, contains('bill'));
      p.dispose();
    });

    test('on-device available → its text used, source onDevice', () async {
      final onDevice =
          availableAi(() => Stream.fromIterable(['System: ', 'settle it.']));
      final p = build(onDeviceAi: onDevice);
      p.inputs = billInputs;
      await p.init();
      await p.refresh();
      expect(p.current!.source, InsightSource.onDevice);
      expect(p.current!.text, 'System: settle it.');
      p.dispose();
    });

    test('on-device empty → falls through to cloud', () async {
      final onDevice = availableAi(() => const Stream<String>.empty());
      final cloud = availableAi(() => Stream.fromIterable(['Cloud line.']));
      final p = build(onDeviceAi: onDevice, cloudAi: cloud);
      p.inputs = billInputs;
      await p.init();
      await p.refresh();
      expect(p.current!.source, InsightSource.cloud);
      expect(p.current!.text, 'Cloud line.');
      p.dispose();
    });

    test('on-device error → falls through to cloud', () async {
      final onDevice =
          availableAi(() => Stream<String>.error(Exception('boom')));
      final cloud = availableAi(() => Stream.fromIterable(['Cloud line.']));
      final p = build(onDeviceAi: onDevice, cloudAi: cloud);
      p.inputs = billInputs;
      await p.init();
      await p.refresh();
      expect(p.current!.source, InsightSource.cloud);
      p.dispose();
    });

    test('cloud daily cap exhausted → rules fallback', () async {
      // Seed 6 cloud-sourced insights today so the cloud cap is spent. Use
      // dailyBrief kind so they don't consume the nudge cap.
      insights = List.generate(
        6,
        (i) => Insight(
          id: 'seed$i',
          kind: InsightKind.dailyBrief,
          mood: InsightMood.neutral,
          text: 'seed',
          createdAt: now,
          source: InsightSource.cloud,
        ),
      );
      final cloud = availableAi(() => Stream.fromIterable(['nope']));
      final p = build(cloudAi: cloud); // no on-device
      p.inputs = billInputs;
      await p.init();
      await p.refresh();

      final nudge = p.recent.firstWhere((i) => i.kind == InsightKind.nudge);
      expect(nudge.source, InsightSource.rules);
      verifyNever(cloud.respond(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
      ));
      p.dispose();
    });
  });

  group('lifecycle', () {
    test('refresh before init is a no-op', () async {
      final p = build();
      p.inputs = billInputs;
      await p.refresh(); // before init
      verifyNever(storage.saveInsightBaselineHashes(any));
      verifyNever(storage.saveInsights(any));
      p.dispose();
    });

    test('init loads persisted insights (survives restart)', () async {
      insights = [
        Insight(
          id: 'old',
          kind: InsightKind.nudge,
          mood: InsightMood.urgent,
          text: 'previous nudge',
          triggerId: 'finance.billImminent',
          createdAt: now,
          source: InsightSource.rules,
        ),
      ];
      final p = build();
      await p.init();
      expect(p.recent.length, 1);
      expect(p.recent.first.text, 'previous nudge');
      p.dispose();
    });

    test('init purges legacy persisted error-text insights', () async {
      // Before AiCoachException, a failed cloud call yielded its error prose
      // as tokens and it got persisted as a real insight — reproduce that
      // stored state and assert init cleans it up.
      insights = [
        Insight(
          id: 'bad-nudge',
          kind: InsightKind.nudge,
          mood: InsightMood.urgent,
          text: 'Cloud coach unreachable. Check your connection and try '
              'again.',
          triggerId: 'finance.billImminent',
          createdAt: now,
          source: InsightSource.cloud,
        ),
        Insight(
          id: 'good',
          kind: InsightKind.nudge,
          mood: InsightMood.neutral,
          text: 'real nudge',
          createdAt: now.subtract(const Duration(days: 1)),
          source: InsightSource.rules,
        ),
      ];
      final p = build();
      await p.init();
      expect(p.recent.length, 1);
      expect(p.recent.first.id, 'good');
      expect(insights.length, 1); // purge persisted
      p.dispose();
    });

    test('purging an error-text daily brief lets today\'s brief regenerate',
        () async {
      insights = [
        Insight(
          id: 'bad-brief',
          kind: InsightKind.dailyBrief,
          mood: InsightMood.neutral,
          text: 'Cloud coach unreachable. Check your connection and try '
              'again.',
          createdAt: now,
          source: InsightSource.cloud,
        ),
      ];
      briefDate = now; // brief already "generated" today — by the bad text
      final p = build();
      p.inputs = benign;
      await p.init();
      expect(p.dailyBrief, isNull);

      await p.generateDailyBriefIfDue(); // must NOT no-op on the stale date
      expect(p.dailyBrief, isNotNull);
      expect(p.dailyBrief!.source, InsightSource.rules);
      expect(p.dailyBrief!.text, isNot(contains('unreachable')));
      p.dispose();
    });

    test('hasUnread + markRead watermark', () async {
      insights = [
        Insight(
          id: 'n1',
          kind: InsightKind.nudge,
          mood: InsightMood.urgent,
          text: 'unread',
          createdAt: now,
          source: InsightSource.rules,
        ),
      ];
      final p = build();
      await p.init();
      expect(p.hasUnread, isTrue);

      p.markRead();
      expect(p.hasUnread, isFalse);
      // Watermark persisted in the cooldown map under the reserved key.
      expect(cooldowns!.containsKey('_lastRead'), isTrue);
      p.dispose();
    });
  });

  group('re-entrancy', () {
    // A phrasing service that yields after a delay, widening the window where
    // two overlapping callers can both slip past the once-a-day / hash gate.
    MockAiCoachService slowAi(String out) {
      final ai = MockAiCoachService();
      when(ai.isAvailable).thenReturn(true);
      when(ai.respond(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
      )).thenAnswer((_) async* {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        yield out;
      });
      return ai;
    }

    test('concurrent generateDailyBriefIfDue generates at most one brief',
        () async {
      final p = build(onDeviceAi: slowAi('brief text'));
      p.inputs = benign;
      await p.init();

      // Two callers in the same turn, before either has set _lastBriefDate.
      final f1 = p.generateDailyBriefIfDue();
      final f2 = p.generateDailyBriefIfDue();
      await Future.wait([f1, f2]);

      expect(
        p.recent.where((i) => i.kind == InsightKind.dailyBrief).length,
        1,
        reason: 'daily brief must generate at most once/day even under overlap',
      );
      p.dispose();
    });

    test('concurrent refresh does not double-fire a nudge', () async {
      final p = build(onDeviceAi: slowAi('phrased'));
      p.inputs = billInputs; // fires finance.billImminent
      await p.init();

      final f1 = p.refresh();
      final f2 = p.refresh();
      await Future.wait([f1, f2]);

      expect(nudgeCount(p), 1,
          reason: 'overlapping refreshes must coalesce, not double-fire');
      p.dispose();
    });
  });

  group('debounce', () {
    test('bursts of source changes coalesce into one refresh', () async {
      final p = build();
      p.inputs = benign;
      await p.init();
      final before = p.refreshCalls;

      p.debugSimulateSourceChange();
      p.debugSimulateSourceChange();
      p.debugSimulateSourceChange();
      await Future<void>.delayed(Duration.zero);

      expect(p.refreshCalls - before, 1);
      p.dispose();
    });
  });
}
