import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_event.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/image_compressor.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';
import '../support/proposal_fakes.dart';

class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

/// Parks every proposal behind a card until someone answers it, the way
/// `FinanceActionsExecutor` does, so a test can stop the turn while the card
/// is open.
class _CardExecutor extends ChangeNotifier
    with ProposeBatchOneByOne, SingleProposalBatch
    implements FinanceToolExecutor, FinanceProposalHost {
  PendingFinanceAction? _pending;
  Completer<AiToolResult>? _decision;
  final List<AiToolResult> answers = [];

  @override
  PendingFinanceAction? get pending => _pending;

  @override
  Future<AiToolResult> runRead(AiToolCall call) async =>
      AiToolResult(toolUseId: call.id, ok: true, summary: 'found 1 match');

  @override
  Future<AiToolResult> propose(AiToolCall call) {
    _pending = PendingFinanceAction(
      call: call,
      title: 'Set aside ₱3,000 for Braces',
      details: const [],
      isRecurring: false,
    );
    _decision = Completer<AiToolResult>();
    notifyListeners();
    return _decision!.future;
  }

  @override
  Future<void> confirm(
          {bool applyToFuture = false, bool? alreadyLogged}) async =>
      _answer(AiToolResult(
          toolUseId: _pending!.call.id, ok: true, summary: 'saved'));

  @override
  void decline() => _answer(AiToolResult.declined(_pending!.call.id));

  void _answer(AiToolResult result) {
    final decision = _decision;
    if (decision == null) return;
    _pending = null;
    _decision = null;
    answers.add(result);
    decision.complete(result);
    notifyListeners();
  }
}

/// Lets the presenter's microtasks and zero-length timers run.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The ids of tool_use blocks that the next message does not answer with a
/// tool_result. The provider rejects a request holding any of them.
List<String> _danglingToolUses(List<AiChatMessage> messages) {
  final dangling = <String>[];
  for (var i = 0; i < messages.length; i++) {
    final uses = messages[i]
        .contentBlocks
        .where((b) => b['type'] == 'tool_use')
        .map((b) => b['id'] as String);
    final answered = i + 1 < messages.length
        ? messages[i + 1]
            .contentBlocks
            .where((b) => b['type'] == 'tool_result')
            .map((b) => b['tool_use_id'])
            .toSet()
        : const <Object?>{};
    dangling.addAll(uses.where((id) => !answered.contains(id)));
  }
  return dangling;
}

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

  /// Answers each successive hop from [script], in order.
  void scriptStreams(List<Stream<AdvisorEvent> Function()> script) {
    var i = 0;
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
    )).thenAnswer((_) => script[i++]());
  }

  List<List<AiChatMessage>> sentHistories() => verify(service.adviseFinance(
        messages: captureAnyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        tools: anyNamed('tools'),
      )).captured.cast<List<AiChatMessage>>();

  AiCoachPresenter build({FinanceToolExecutor? executor}) {
    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      imageCompressor: _PassthroughCompressor(),
      toolExecutor: executor,
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    return p;
  }

  test('stop mid-stream keeps the partial reply, marked stopped', () async {
    final hop = StreamController<AdvisorEvent>();
    scriptStreams([() => hop.stream]);
    final p = build();

    final turn = p.send('plan my month');
    await _settle();
    expect(p.isWorking, isTrue);
    expect(p.canStop, isTrue);

    hop
      ..add(const AdvisorEvent.start())
      ..add(const AdvisorEvent.delta('Start with rent, '))
      ..add(const AdvisorEvent.delta('then groceries'));
    await _settle();

    p.stop();
    expect(p.canStop, isFalse, reason: 'a second tap is not a second stop');
    await turn;

    expect(
        p.messages.last.text, 'Start with rent, then groceries\n\n_Stopped._');
    expect(p.messages.last.isStreaming, isFalse);
    expect(p.isWorking, isFalse);
    expect(p.isResponding, isFalse);
    expect(p.errorMessage, isNull, reason: 'a stop is not a failure');
    expect(p.canRetryLastTurn, isFalse);
    // The subscription is cancelled, which ends the service's generator and
    // closes its HTTP client.
    expect(hop.hasListener, isFalse);

    // Words that arrive after the stop change nothing.
    hop.add(const AdvisorEvent.delta(' and savings'));
    await _settle();
    expect(
        p.messages.last.text, 'Start with rent, then groceries\n\n_Stopped._');
    p.dispose();
  });

  test('stop before the first word still marks the reply stopped', () async {
    // The model is still thinking: no event has arrived, so only the wrapper
    // can end the wait.
    final hop = StreamController<AdvisorEvent>();
    scriptStreams([() => hop.stream]);
    final p = build();

    final turn = p.send('plan my month');
    await _settle();
    p.stop();
    await turn;

    expect(p.messages.last.text, '_Stopped._');
    expect(p.isWorking, isFalse);
    expect(hop.hasListener, isFalse);
    p.dispose();
  });

  test('stop with a card open declines it and starts no next hop', () async {
    final executor = _CardExecutor();
    var hops = 0;
    scriptStreams([
      () {
        hops++;
        return advisorStreamOf(const AdvisorReply(
          text: 'Sure, I can set that aside.',
          toolCalls: [AiToolCall(id: 'tu_1', name: 'addSetAside', input: {})],
          assistantContent: [
            {
              'type': 'tool_use',
              'id': 'tu_1',
              'name': 'addSetAside',
              'input': {}
            }
          ],
        ));
      },
      () {
        hops++;
        return advisorStreamOf(const AdvisorReply(text: 'Saved it.'));
      },
    ]);
    final p = build(executor: executor);

    final turn = p.send('set aside 3000 for braces');
    await _settle();
    expect(executor.pending, isNotNull, reason: 'the card is on screen');
    expect(p.canStop, isTrue, reason: 'Nudgy is still working on the turn');

    p.stop();
    await turn;

    expect(executor.pending, isNull);
    expect(executor.answers.single.ok, isFalse);
    expect(executor.answers.single.summary, contains('declined'));
    expect(hops, 1, reason: 'no hop starts after a stop');
    expect(p.messages.last.text, 'Sure, I can set that aside.\n\n_Stopped._');
    expect(p.isWorking, isFalse);
    p.dispose();
  });

  test('the request after a stop holds no tool_use without a result', () async {
    final executor = _CardExecutor();
    scriptStreams([
      () => advisorStreamOf(const AdvisorReply(
            text: 'Sure, I can set that aside.',
            toolCalls: [AiToolCall(id: 'tu_1', name: 'addSetAside', input: {})],
            assistantContent: [
              {
                'type': 'tool_use',
                'id': 'tu_1',
                'name': 'addSetAside',
                'input': {}
              }
            ],
          )),
      () => advisorStreamOf(const AdvisorReply(text: 'Left it alone.')),
    ]);
    final p = build(executor: executor);

    final turn = p.send('set aside 3000 for braces');
    await _settle();
    p.stop();
    await turn;

    await p.send('actually, never mind');

    final histories = sentHistories();
    expect(histories, hasLength(2));
    final next = histories.last;
    expect(_danglingToolUses(next), isEmpty);
    expect(next.every((m) => m.contentBlocks.isEmpty), isTrue,
        reason: 'the stopped turn replays as plain text only');
    expect(
      next.map((m) => m.text),
      containsAllInOrder([
        'set aside 3000 for braces',
        'Sure, I can set that aside.\n\n_Stopped._',
        'actually, never mind',
      ]),
    );
    expect(p.messages.last.text, 'Left it alone.');
    p.dispose();
  });

  test('stop does nothing when Nudgy is not working', () async {
    scriptStreams(
        [() => advisorStreamOf(const AdvisorReply(text: 'You are fine.'))]);
    final p = build();
    await p.send('how am I doing?');

    expect(p.isWorking, isFalse);
    expect(p.canStop, isFalse);
    p.stop();

    expect(p.messages.last.text, 'You are fine.');
    p.dispose();
  });
}
