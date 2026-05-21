import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/finance_dict_entry.dart';
import 'package:intermittent_fasting/services/finance_personal_dictionary.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockStorageService storage;
  late FinancePersonalDictionary dict;

  setUp(() {
    storage = MockStorageService();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadFinanceDictionary())
        .thenAnswer((_) async => <FinanceDictEntry>[]);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    dict = FinancePersonalDictionary(storage);
  });

  group('normalizeToken', () {
    test('lowercases and strips punctuation', () {
      expect(
          FinancePersonalDictionary.normalizeToken('Hamburger!'), 'hamburger');
    });

    test('empty for whitespace only', () {
      expect(FinancePersonalDictionary.normalizeToken('   '), '');
    });
  });

  group('learn / lookup', () {
    test('learn then lookup returns categoryId', () async {
      await dict.init();
      await dict.learn('hamburger', 'food');
      expect(dict.lookup('hamburger'), 'food');
    });

    test('lookup is normalized — punctuation insensitive', () async {
      await dict.init();
      await dict.learn('Uber', 'transport');
      expect(dict.lookup('UBER!'), 'transport');
      expect(dict.lookup('  uber  '), 'transport');
    });

    test('missing token returns null', () async {
      await dict.init();
      expect(dict.lookup('nothing'), isNull);
    });

    test('relearning overwrites mapping (latest wins)', () async {
      await dict.init();
      await dict.learn('hamburger', 'food');
      await dict.learn('hamburger', 'snacks');
      expect(dict.lookup('hamburger'), 'snacks');
    });

    test('learn persists via storage', () async {
      await dict.init();
      await dict.learn('uber', 'transport');
      verify(storage.saveFinanceDictionary(any)).called(1);
    });

    test('learn ignores empty tokens', () async {
      await dict.init();
      await dict.learn('   ', 'food');
      expect(dict.lookup(''), isNull);
      verifyNever(storage.saveFinanceDictionary(any));
    });
  });

  group('remove + cascade', () {
    test('remove drops a single mapping', () async {
      await dict.init();
      await dict.learn('hamburger', 'food');
      await dict.remove('hamburger');
      expect(dict.lookup('hamburger'), isNull);
    });

    test('removeForCategory drops every token pointing at it', () async {
      await dict.init();
      await dict.learn('hamburger', 'food');
      await dict.learn('pizza', 'food');
      await dict.learn('uber', 'transport');

      final removed = await dict.removeForCategory('food');

      expect(removed, 2);
      expect(dict.lookup('hamburger'), isNull);
      expect(dict.lookup('pizza'), isNull);
      expect(dict.lookup('uber'), 'transport');
    });

    test('removeForCategory with no matches is a no-op', () async {
      await dict.init();
      await dict.learn('uber', 'transport');
      clearInteractions(storage);

      final removed = await dict.removeForCategory('nonexistent');

      expect(removed, 0);
      verifyNever(storage.saveFinanceDictionary(any));
    });
  });

  group('persistence round-trip', () {
    test('init reads stored entries into the in-memory map', () async {
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => [
            FinanceDictEntry(
              token: 'pizza',
              categoryId: 'food',
              lastUsedAt: DateTime(2026, 1, 1),
            ),
          ]);
      final loaded = FinancePersonalDictionary(storage);
      await loaded.init();
      expect(loaded.lookup('pizza'), 'food');
    });

    test('snapshot returns full map for prompt building', () async {
      await dict.init();
      await dict.learn('uber', 'transport');
      await dict.learn('pizza', 'food');
      final snap = dict.snapshot();
      expect(snap, containsPair('uber', 'transport'));
      expect(snap, containsPair('pizza', 'food'));
    });
  });
}
