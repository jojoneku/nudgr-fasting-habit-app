// Phase 2 (Plan 057 — Hub AI Insights & Nudges): StorageService additions for
// the Insight Engine. Round-trips each of the four new save/load pairs,
// confirms null/absent-key behavior, and overwrite semantics.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/models/insight.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';

void main() {
  late LocalStorageService svc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc = LocalStorageService();
  });

  // ── Insight baseline hashes ─────────────────────────────────────────────────

  group('StorageService — insight baseline hashes', () {
    test('returns null when nothing saved', () async {
      expect(await svc.loadInsightBaselineHashes(), isNull);
    });

    test('save / load round-trips section → hash map', () async {
      final hashes = {
        'fasting': 'abc123',
        'nutrition': 'def456',
        'finance': 'ghi789',
      };
      await svc.saveInsightBaselineHashes(hashes);
      final loaded = await svc.loadInsightBaselineHashes();
      expect(loaded, hashes);
    });

    test('save overwrites the previous baseline entirely', () async {
      await svc.saveInsightBaselineHashes({'fasting': 'old', 'body': 'stale'});
      await svc.saveInsightBaselineHashes({'fasting': 'new'});
      final loaded = await svc.loadInsightBaselineHashes();
      expect(loaded, {'fasting': 'new'});
      expect(loaded!.containsKey('body'), false);
    });
  });

  // ── Insights ring buffer ─────────────────────────────────────────────────────

  group('StorageService — insights', () {
    test('returns empty list when nothing saved', () async {
      expect(await svc.loadInsights(), isEmpty);
    });

    test('save / load round-trips full Insight field fidelity', () async {
      final createdAt = DateTime(2026, 7, 12, 7, 30, 15, 123, 456);
      final brief = Insight(
        id: 'brief-1',
        kind: InsightKind.dailyBrief,
        mood: InsightMood.neutral,
        text: 'System Analysis complete. All vitals nominal.',
        triggerId: null,
        createdAt: createdAt,
        source: InsightSource.onDevice,
      );
      final nudge = Insight(
        id: 'nudge-1',
        kind: InsightKind.nudge,
        mood: InsightMood.urgent,
        text: "You've exceeded today's calorie goal.",
        triggerId: 'nutrition.overGoal',
        createdAt: createdAt.add(const Duration(minutes: 5)),
        source: InsightSource.cloud,
      );

      await svc.saveInsights([brief, nudge]);
      final loaded = await svc.loadInsights();

      expect(loaded, hasLength(2));
      expect(loaded[0].id, 'brief-1');
      expect(loaded[0].kind, InsightKind.dailyBrief);
      expect(loaded[0].mood, InsightMood.neutral);
      expect(loaded[0].text, brief.text);
      expect(loaded[0].triggerId, isNull);
      expect(loaded[0].createdAt, createdAt);
      expect(loaded[0].source, InsightSource.onDevice);

      expect(loaded[1].id, 'nudge-1');
      expect(loaded[1].kind, InsightKind.nudge);
      expect(loaded[1].mood, InsightMood.urgent);
      expect(loaded[1].triggerId, 'nutrition.overGoal');
      expect(loaded[1].createdAt, createdAt.add(const Duration(minutes: 5)));
      expect(loaded[1].source, InsightSource.cloud);
    });

    test('save overwrites the previous list (no trimming — caller\'s job)',
        () async {
      final now = DateTime(2026, 7, 12);
      final many = List.generate(
        40,
        (i) => Insight(
          id: 'i$i',
          kind: InsightKind.nudge,
          mood: InsightMood.positive,
          text: 'nudge $i',
          triggerId: 'positive.onFire',
          createdAt: now.add(Duration(minutes: i)),
          source: InsightSource.rules,
        ),
      );
      await svc.saveInsights(many);
      final loaded = await svc.loadInsights();
      // Storage stores exactly what it's given — trimming to <=30 is a
      // caller responsibility, not enforced here.
      expect(loaded, hasLength(40));

      await svc.saveInsights([many.first]);
      expect(await svc.loadInsights(), hasLength(1));
    });
  });

  // ── Insight cooldowns ────────────────────────────────────────────────────────

  group('StorageService — insight cooldowns', () {
    test('returns null when nothing saved', () async {
      expect(await svc.loadInsightCooldowns(), isNull);
    });

    test('save / load round-trips trigger id → DateTime with precision',
        () async {
      final fired = DateTime(2026, 7, 12, 8, 15, 30, 500, 250);
      final cooldowns = {
        'nutrition.overGoal': fired,
        'finance.spendPace': fired.add(const Duration(hours: 3)),
      };
      await svc.saveInsightCooldowns(cooldowns);
      final loaded = await svc.loadInsightCooldowns();

      expect(loaded, hasLength(2));
      expect(loaded!['nutrition.overGoal'], fired);
      expect(loaded['finance.spendPace'], fired.add(const Duration(hours: 3)));
    });

    test('save overwrites the previous cooldown map entirely', () async {
      final t1 = DateTime(2026, 7, 1);
      final t2 = DateTime(2026, 7, 2);
      await svc.saveInsightCooldowns({'a.trigger': t1, 'b.trigger': t1});
      await svc.saveInsightCooldowns({'a.trigger': t2});
      final loaded = await svc.loadInsightCooldowns();
      expect(loaded, {'a.trigger': t2});
      expect(loaded!.containsKey('b.trigger'), false);
    });
  });

  // ── Last daily brief date ────────────────────────────────────────────────────

  group('StorageService — last daily brief date', () {
    test('returns null when nothing saved', () async {
      expect(await svc.loadLastDailyBriefDate(), isNull);
    });

    test('save / load round-trips with full precision', () async {
      final date = DateTime(2026, 7, 12, 0, 0, 0, 1, 1);
      await svc.saveLastDailyBriefDate(date);
      expect(await svc.loadLastDailyBriefDate(), date);
    });

    test('save overwrites the previous date', () async {
      await svc.saveLastDailyBriefDate(DateTime(2026, 7, 11));
      await svc.saveLastDailyBriefDate(DateTime(2026, 7, 12));
      expect(await svc.loadLastDailyBriefDate(), DateTime(2026, 7, 12));
    });
  });

  // ── User scoping ─────────────────────────────────────────────────────────────

  group('StorageService — insight data is user-scoped', () {
    test('data saved before setUserId migrates into the scoped namespace',
        () async {
      await svc.saveLastDailyBriefDate(DateTime(2026, 7, 10));
      await svc.saveInsightBaselineHashes({'fasting': 'x'});

      await svc.setUserId('user-42');

      expect(await svc.loadLastDailyBriefDate(), DateTime(2026, 7, 10));
      expect(await svc.loadInsightBaselineHashes(), {'fasting': 'x'});
    });

    test('clearUserData wipes insight data for that user', () async {
      await svc.setUserId('user-42');
      await svc.saveLastDailyBriefDate(DateTime(2026, 7, 10));
      await svc.saveInsights([
        Insight(
          id: 'i1',
          kind: InsightKind.nudge,
          mood: InsightMood.neutral,
          text: 'x',
          createdAt: DateTime(2026, 7, 10),
          source: InsightSource.rules,
        ),
      ]);

      await svc.clearUserData();
      await svc.setUserId('user-42');

      expect(await svc.loadLastDailyBriefDate(), isNull);
      expect(await svc.loadInsights(), isEmpty);
    });
  });
}
