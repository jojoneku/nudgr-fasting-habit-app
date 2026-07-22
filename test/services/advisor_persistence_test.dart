import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/models/advisor_profile.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';

void main() {
  late LocalStorageService svc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc = LocalStorageService();
  });

  group('Advisor history persistence', () {
    test('round-trips messages, dropping streaming/empty', () async {
      final msgs = [
        AiChatMessage.user('how am I doing?'),
        AiChatMessage(
          id: 'a1',
          role: AiChatRole.assistant,
          text: 'You are on track.',
          timestamp: _fixedTime,
        ),
        AiChatMessage.assistantStreaming(), // must be dropped (streaming/empty)
      ];
      await svc.saveAdvisorHistory(msgs);
      final loaded = await svc.loadAdvisorHistory();

      expect(loaded.length, 2);
      expect(loaded[0].role, AiChatRole.user);
      expect(loaded[0].text, 'how am I doing?');
      expect(loaded[1].text, 'You are on track.');
      expect(loaded.every((m) => !m.isStreaming), isTrue);
    });

    test('empty when nothing saved', () async {
      expect(await svc.loadAdvisorHistory(), isEmpty);
    });

    test('caps to the newest 100 turns', () async {
      final many = List.generate(
        130,
        (i) => AiChatMessage(
          id: 'm$i',
          role: AiChatRole.user,
          text: 'msg $i',
          timestamp: _fixedTime,
        ),
      );
      await svc.saveAdvisorHistory(many);
      final loaded = await svc.loadAdvisorHistory();
      expect(loaded.length, 100);
      // Kept the newest.
      expect(loaded.first.text, 'msg 30');
      expect(loaded.last.text, 'msg 129');
    });

    test('clear removes history', () async {
      await svc.saveAdvisorHistory([AiChatMessage.user('hi there 100')]);
      expect(await svc.loadAdvisorHistory(), isNotEmpty);
      await svc.clearAdvisorHistory();
      expect(await svc.loadAdvisorHistory(), isEmpty);
    });
  });

  group('Advisor profile persistence', () {
    test('round-trips goals, risk tolerance, and facts', () async {
      final profile = AdvisorProfile(
        goals: const ['Save ₱100k emergency fund', 'Start investing'],
        riskTolerance: 'moderate builder',
        facts: const ['Supports parents monthly'],
        updatedAt: _fixedTime,
      );
      await svc.saveAdvisorProfile(profile);
      final loaded = await svc.loadAdvisorProfile();

      expect(loaded, isNotNull);
      expect(loaded!.goals, profile.goals);
      expect(loaded.riskTolerance, 'moderate builder');
      expect(loaded.facts, profile.facts);
    });

    test('null when nothing saved', () async {
      expect(await svc.loadAdvisorProfile(), isNull);
    });

    test('promptSummary omits empty profile and renders a populated one', () {
      expect(AdvisorProfile.empty().promptSummary(), isNull);
      final p = AdvisorProfile(
        goals: const ['Emergency fund'],
        updatedAt: _fixedTime,
      );
      expect(p.promptSummary(), contains('Emergency fund'));
    });
  });
}

final _fixedTime = DateTime.utc(2026, 7, 22, 12);
