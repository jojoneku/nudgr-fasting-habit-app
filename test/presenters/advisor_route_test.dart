import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/cloud_ai_coach_service.dart';
import 'package:intermittent_fasting/services/image_compressor.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';
import '../support/proposal_fakes.dart';

/// Haiku routing (Plan 065, phase 5): the route is fixed per conversation,
/// on its first advisor message, and sent with every hop. It only ever moves
/// from haiku to sonnet, never back, because each model writes its own cache
/// of the same history.
class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

class _ReadExecutor with ProposeBatchOneByOne implements FinanceToolExecutor {
  @override
  Future<AiToolResult> runRead(AiToolCall call) async =>
      AiToolResult(toolUseId: call.id, ok: true, summary: 'found 1 match');

  @override
  Future<AiToolResult> propose(AiToolCall call) async =>
      AiToolResult.declined(call.id);
}

AdvisorReply _toolTurn(String name,
        [Map<String, Object?> input = const {'entity': 'bill'}]) =>
    AdvisorReply(
      toolCalls: [AiToolCall(id: 'tu_1', name: name, input: input)],
      assistantContent: [
        {'type': 'tool_use', 'id': 'tu_1', 'name': name, 'input': input}
      ],
    );

const _answer = AdvisorReply(text: 'Done.');

void main() {
  late MockStatsPresenter stats;
  late MockFastingPresenter fasting;
  late MockAiCoachService service;

  setUp(() {
    stats = MockStatsPresenter();
    fasting = MockFastingPresenter();
    service = MockAiCoachService();
    when(stats.stats).thenReturn(UserStats.initial());
    when(fasting.isFasting).thenReturn(false);
    when(fasting.fastingGoalHours).thenReturn(16);
    when(service.isAvailable).thenReturn(true);
    when(service.tier).thenReturn(AiCoachTier.cloud);
  });

  void scriptReplies(List<AdvisorReply> script) {
    var i = 0;
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
      route: anyNamed('route'),
    )).thenAnswer((_) {
      final reply = script[i < script.length ? i : script.length - 1];
      i++;
      return advisorStreamOf(reply);
    });
  }

  List<String?> sentRoutes() => verify(service.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        tools: anyNamed('tools'),
        route: captureAnyNamed('route'),
      )).captured.cast<String?>();

  AiCoachPresenter build() => AiCoachPresenter(
        stats: stats,
        fasting: fasting,
        service: service,
        imageCompressor: _PassthroughCompressor(),
        toolExecutor: _ReadExecutor(),
      )..openSession(AiCoachEntryPoint.financeAdvisor);

  test('a lookup conversation runs every hop and every turn on haiku',
      () async {
    scriptReplies([_toolTurn('find'), _answer, _answer]);
    final p = build();

    await p.send('What bills are due this week?');
    // A later turn with planning words does not move it.
    await p.send('Should I pay them early?');

    expect(sentRoutes(), ['haiku', 'haiku', 'haiku']);
    p.dispose();
  });

  test('a conversation that starts with a plan stays on sonnet', () async {
    scriptReplies([_answer]);
    final p = build();

    await p.send('I want to save for a trip next year');
    await p.send('What is my cash balance?');

    expect(sentRoutes(), ['sonnet', 'sonnet']);
    p.dispose();
  });

  test('a new conversation decides its route again', () async {
    scriptReplies([_answer]);
    final p = build();

    await p.send('Add a bill for 500');
    p.startNewConversation();
    await p.send('What is my cash balance?');

    expect(sentRoutes(), ['sonnet', 'haiku']);
    p.dispose();
  });

  test('an unknown tool escalates to sonnet from the next hop on', () async {
    scriptReplies([_toolTurn('summonDragon'), _answer, _answer]);
    final p = build();

    await p.send('What bills are due this week?');
    await p.send('And next week?');

    expect(sentRoutes(), ['haiku', 'sonnet', 'sonnet']);
    p.dispose();
  });

  test('an input that breaks the schema escalates to sonnet', () async {
    scriptReplies([
      _toolTurn('queryFinance', {'metric': 'banana'}),
      _answer,
    ]);
    final p = build();

    await p.send('What did I spend in August?');

    expect(sentRoutes(), ['haiku', 'sonnet']);
    p.dispose();
  });

  test('a valid tool call keeps the conversation on haiku', () async {
    scriptReplies([
      _toolTurn('queryFinance', {'metric': 'spend', 'month': '2026-08'}),
      _answer,
    ]);
    final p = build();

    await p.send('What did I spend in August?');

    expect(sentRoutes(), ['haiku', 'haiku']);
    p.dispose();
  });

  test('the hop ceiling escalates the conversation to sonnet for good',
      () async {
    // Every reply asks for another tool, so the turn runs out of hops.
    scriptReplies([
      for (var i = 0; i < AiCoachPresenter.maxToolHops; i++) _toolTurn('find'),
      _answer,
    ]);
    final p = build();

    await p.send('What bills are due this week?');
    await p.send('What is my cash balance?');

    final routes = sentRoutes();
    expect(routes.take(AiCoachPresenter.maxToolHops), everyElement('haiku'));
    expect(routes.last, 'sonnet');
    p.dispose();
  });

  test('the route field reaches the request payload', () {
    final payload = CloudAiCoachService.advisorPayload(
      messages: [AiChatMessage.user('hi')],
      context: const AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
      ),
      route: 'haiku',
    );
    expect(payload['route'], 'haiku');

    final none = CloudAiCoachService.advisorPayload(
      messages: [AiChatMessage.user('hi')],
      context: const AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
      ),
    );
    expect(none.containsKey('route'), isFalse);
  });
}
