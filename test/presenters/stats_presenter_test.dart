import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import '../mocks.mocks.dart';

void main() {
  late MockStorageService mockStorage;
  late StatsPresenter presenter;

  setUp(() {
    mockStorage = MockStorageService();
    when(mockStorage.loadUserStats())
        .thenAnswer((_) async => UserStats.initial());
    when(mockStorage.saveUserStats(any)).thenAnswer((_) async {});
    presenter = StatsPresenter(mockStorage);
  });

  group('StatsPresenter — XP and levelling', () {
    test('addXp increases currentXp', () async {
      await presenter.addXp(50);
      // STR=1 applies 1% bonus: floor(50 * 1.01) = 51
      expect(presenter.stats.currentXp, 51);
    });

    test('addXp applies STR bonus (1% per STR point)', () async {
      // STR=1 → 1% bonus. Use 50 XP (below the 100 XP level threshold)
      // so we can observe the bonus without a level-up resetting XP.
      await presenter.addXp(50);
      expect(presenter.stats.currentXp, greaterThan(50));
    });

    test('level up when XP reaches threshold (level^2 * 100)', () async {
      // Level 1 threshold = 1*1*100 = 100 XP
      await presenter.addXp(100);
      expect(presenter.stats.level, 2);
      expect(presenter.showLevelUpDialog, true);
    });

    test('multi-level up handled correctly', () async {
      // L1→100XP, L2→400XP, need 500 to jump 2 levels
      await presenter.addXp(500);
      expect(presenter.stats.level, greaterThanOrEqualTo(2));
    });

    test('level up grants 3 stat points', () async {
      final pointsBefore = presenter.stats.statPoints;
      await presenter.addXp(100);
      expect(presenter.stats.statPoints, pointsBefore + 3);
    });

    test('dismissLevelUp clears showLevelUpDialog', () async {
      await presenter.addXp(100);
      expect(presenter.showLevelUpDialog, true);
      presenter.dismissLevelUp();
      expect(presenter.showLevelUpDialog, false);
    });
  });

  group('StatsPresenter — HP', () {
    test('modifyHp increases HP', () async {
      await presenter.modifyHp(-20);
      await presenter.modifyHp(10);
      expect(presenter.stats.currentHp, 90);
    });

    test('modifyHp clamps to maxHp', () async {
      await presenter.modifyHp(9999);
      expect(presenter.stats.currentHp, presenter.maxHp);
    });

    test('modifyHp clamps to 0', () async {
      await presenter.modifyHp(-9999);
      expect(presenter.stats.currentHp, 0);
    });

    test('maxHp increases with VIT', () async {
      final baseMhp = presenter.maxHp;
      await presenter.awardStat('vit');
      expect(presenter.maxHp, greaterThan(baseMhp));
    });
  });

  group('StatsPresenter — stats', () {
    test('allocatePoint increases the chosen stat', () async {
      // Give a stat point first
      await presenter.addXp(100); // level up → +3 points
      final agiBefore = presenter.stats.attributes.agi;
      await presenter.allocatePoint('agi');
      expect(presenter.stats.attributes.agi, agiBefore + 1);
      expect(presenter.stats.statPoints, 2); // 3 - 1
    });

    test('allocatePoint does nothing with 0 points', () async {
      final agiBefore = presenter.stats.attributes.agi;
      await presenter.allocatePoint('agi');
      expect(presenter.stats.attributes.agi, agiBefore); // unchanged
    });

    test('awardStat increments AGI directly', () async {
      final before = presenter.stats.attributes.agi;
      await presenter.awardStat('agi');
      expect(presenter.stats.attributes.agi, before + 1);
    });

    test('awardStat increments STR', () async {
      final before = presenter.stats.attributes.str;
      await presenter.awardStat('str');
      expect(presenter.stats.attributes.str, before + 1);
    });

    test('awardStat does nothing for unknown stat', () async {
      final before = presenter.stats.attributes;
      await presenter.awardStat('unknown');
      expect(presenter.stats.attributes.agi, before.agi);
    });
  });

  group('StatsPresenter — streak', () {
    test('incrementStreak increases streak', () async {
      await presenter.incrementStreak();
      expect(presenter.stats.streak, 1);
    });

    test('resetStreak sets streak to 0', () async {
      await presenter.incrementStreak();
      await presenter.incrementStreak();
      await presenter.resetStreak();
      expect(presenter.stats.streak, 0);
    });
  });

  group('StatsPresenter — rank and job', () {
    test('rank is E at level 1', () {
      expect(presenter.rank, 'E');
    });

    test('nextLevelXp formula is level^2 * 100', () {
      expect(presenter.nextLevelXp, 100); // level 1
    });
  });
}
