import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/hub_hero_slots.dart';

void main() {
  group('resolveHeroSlots', () {
    test('default Fast/Food/Move for fasters when unconfigured', () {
      final slots = resolveHeroSlots(configured: null, hasEverFasted: true);
      expect(slots, kDefaultHeroSlots);
      expect(slots.first, HubHeroSlot.fast);
    });

    test('non-faster default puts macro-split in slot 1', () {
      final slots = resolveHeroSlots(configured: null, hasEverFasted: false);
      expect(slots, kNonFasterHeroSlots);
      expect(slots.first, HubHeroSlot.macros);
    });

    test('explicit config wins over the auto-default', () {
      const custom = [HubHeroSlot.move, HubHeroSlot.macros, HubHeroSlot.fast];
      final slots = resolveHeroSlots(configured: custom, hasEverFasted: false);
      expect(slots, custom);
    });

    test('malformed config (wrong length) falls back to default', () {
      final slots = resolveHeroSlots(
          configured: const [HubHeroSlot.fast], hasEverFasted: true);
      expect(slots, kDefaultHeroSlots);
    });
  });

  group('heroSlotFromName', () {
    test('round-trips enum names', () {
      for (final s in HubHeroSlot.values) {
        expect(heroSlotFromName(s.name), s);
      }
    });

    test('returns null for unknown', () {
      expect(heroSlotFromName('bogus'), isNull);
    });
  });
}
