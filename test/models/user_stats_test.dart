import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/user_stats.dart';

void main() {
  group('UserStats', () {
    test('initial() has sane defaults', () {
      final stats = UserStats.initial();
      expect(stats.level, 1);
      expect(stats.currentXp, 0);
      expect(stats.streak, 0);
      expect(stats.attributes.agi, 1);
    });

    test('fromJson/toJson round-trip', () {
      final stats = UserStats(
        name: 'Shadow',
        level: 5,
        currentXp: 250,
        currentHp: 80,
        statPoints: 3,
        streak: 7,
        attributes: (str: 2, vit: 3, agi: 4, intl: 1, sen: 2),
      );
      final restored = UserStats.fromJson(stats.toJson());
      expect(restored.name, stats.name);
      expect(restored.level, stats.level);
      expect(restored.currentXp, stats.currentXp);
      expect(restored.attributes.agi, stats.attributes.agi);
      expect(restored.streak, stats.streak);
    });

    test('copyWith preserves unchanged fields', () {
      final stats = UserStats.initial();
      final updated = stats.copyWith(level: 2, currentXp: 50);
      expect(updated.level, 2);
      expect(updated.currentXp, 50);
      expect(updated.name, stats.name);
      expect(updated.attributes.str, stats.attributes.str);
    });
  });
}
