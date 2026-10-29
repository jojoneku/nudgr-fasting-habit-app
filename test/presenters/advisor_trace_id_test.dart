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

/// The advisor trace id (Plan 065, phase 2): one id per user message, sent
/// with every hop of it, and a new one for the next message. The server
/// groups its cost lines by it, so an id that changed mid-message would split
/// one message in two, and one that never changed would merge them all.
class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

class _ReadExecutor implements FinanceToolExecutor {
  @override
  Future<AiToolResult> runRead(AiToolCall call) async =>
      AiToolResult(toolUseId: call.id, ok: true, summary: 'found 1 match');

  @override
  Future<AiToolResult> propose(AiToolCall call) async =>
      AiToolResult.declined(call.id);
}

AdvisorReply _toolTurn(String name) => AdvisorReply(
      toolCalls: [AiToolCall(id: 'tu_1', name: name, input: const {})],
      assistantContent: [
        {'type': 'tool_use', 'id': 'tu_1', 'name': name, 'input': {}}
      ],
    );

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
    )).thenAnswer((_) {
      final reply = script[i < script.length ? i : script.length - 1];
      i++;
      return advisorStreamOf(reply);
    });
  }

  List<String?> sentTraceIds() => verify(service.adviseFinance(
        messages: anyNamed('messages'),
        context: captureAnyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        tools: anyNamed('tools'),
      )).captured.cast<AiCoachContext>().map((c) => c.traceId).toList();

  test(
      'every hop of one message shares one id; the next message gets a new one',
      () async {
    scriptReplies([
      _toolTurn('findBills'),
      _toolTurn('findSetAsides'),
      const AdvisorReply(text: 'Two bills are due.'),
      const AdvisorReply(text: 'You are fine.'),
    ]);
    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      imageCompressor: _PassthroughCompressor(),
      toolExecutor: _ReadExecutor(),
    )..openSession(AiCoachEntryPoint.financeAdvisor);

    await p.send('what is due?');
    await p.send('and am I ok?');

    final ids = sentTraceIds();
    expect(ids, hasLength(4));
    expect(ids, everyElement(isNotNull));
    // Message 1 took 3 hops.
    expect(ids[1], ids[0]);
    expect(ids[2], ids[0]);
    // Message 2 is a new message.
    expect(ids[3], isNot(ids[0]));
    p.dispose();
  });

  test('a trace id is 16 hex characters and differs on each call', () {
    final a = AiCoachPresenter.newTraceId();
    final b = AiCoachPresenter.newTraceId();

    expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(b, isNot(a));
  });

  test('the request payload carries the context trace id', () {
    final payload = CloudAiCoachService.advisorPayload(
      messages: [AiChatMessage.user('hi')],
      context: const AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        traceId: '0123456789abcdef',
      ),
    );

    expect(payload['trace_id'], '0123456789abcdef');
  });

  test('a context with no trace id sends no trace_id field', () {
    final payload = CloudAiCoachService.advisorPayload(
      messages: [AiChatMessage.user('hi')],
      context: const AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
      ),
    );

    expect(payload.containsKey('trace_id'), isFalse);
  });

  test('a declined result starts with the text the server reads as declined',
      () {
    // backend/ai-coach/lambda_function.py _DECLINED_PREFIX. Change both or
    // the trace logs every declined card as an error.
    final block = AiToolResult.declined('tu_1').toContentBlock();

    expect(block['is_error'], isTrue);
    expect(block['content'] as String, startsWith('The user declined'));
  });
}
