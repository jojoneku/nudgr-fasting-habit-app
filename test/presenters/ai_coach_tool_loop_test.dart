import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
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

class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

/// Records what it was asked to do and answers from a script, so a test can
/// tell a read (executed) from a mutation (proposed) without a real presenter.
class _RecordingExecutor implements FinanceToolExecutor {
  _RecordingExecutor({this.declineProposals = false});

  final bool declineProposals;
  final List<String> reads = [];
  final List<String> proposals = [];

  /// Called while the tool is "running", before it answers. The status strip
  /// only exists to describe this window, so a test cannot check it from the
  /// outside — it has to look from in here.
  void Function()? onCall;

  @override
  Future<AiToolResult> runRead(AiToolCall call) async {
    reads.add(call.name);
    onCall?.call();
    return AiToolResult(toolUseId: call.id, ok: true, summary: 'found 1 match');
  }

  @override
  Future<AiToolResult> propose(AiToolCall call) async {
    proposals.add(call.name);
    onCall?.call();
    return declineProposals
        ? AiToolResult.declined(call.id)
        : AiToolResult(toolUseId: call.id, ok: true, summary: 'saved');
  }
}

AiToolCall _call(String name, [String id = 'tu_1']) =>
    AiToolCall(id: id, name: name, input: const {});

AdvisorReply _toolTurn(String name, {String text = ''}) => AdvisorReply(
      text: text,
      toolCalls: [_call(name)],
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

  /// Answers each successive call from [script], repeating the last entry.
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

  List<AiTool> capturedTools() => verify(service.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        tools: captureAnyNamed('tools'),
      )).captured.first as List<AiTool>;

  test('a turn needing no tool answers in one hop', () async {
    scriptReplies([const AdvisorReply(text: 'You are fine.')]);
    final executor = _RecordingExecutor();
    final p = build(executor: executor);

    await p.send('how am I doing?');

    expect(p.messages.last.text, 'You are fine.');
    expect(executor.reads, isEmpty);
    expect(executor.proposals, isEmpty);
    p.dispose();
  });

  test('a read tool runs and the answer comes back on the next hop', () async {
    scriptReplies([
      _toolTurn('findSetAsides'),
      const AdvisorReply(text: 'You have ₱2,000 set aside for braces.'),
    ]);
    final executor = _RecordingExecutor();
    final p = build(executor: executor);

    await p.send('how is my braces fund?');

    expect(executor.reads, ['findSetAsides']);
    // A read is never routed through the confirm card.
    expect(executor.proposals, isEmpty);
    expect(p.messages.last.text, 'You have ₱2,000 set aside for braces.');
    p.dispose();
  });

  test('a mutating tool is proposed, never executed directly', () async {
    scriptReplies([
      _toolTurn('addSetAside'),
      const AdvisorReply(text: 'Added.'),
    ]);
    final executor = _RecordingExecutor();
    final p = build(executor: executor);

    await p.send('set aside 3000 for braces');

    expect(executor.proposals, ['addSetAside']);
    expect(executor.reads, isEmpty);
    p.dispose();
  });

  test('a declined proposal still ends the turn cleanly', () async {
    scriptReplies([
      _toolTurn('addSetAside'),
      const AdvisorReply(text: 'No problem, left it alone.'),
    ]);
    final executor = _RecordingExecutor(declineProposals: true);
    final p = build(executor: executor);

    await p.send('set aside 3000 for braces');

    expect(executor.proposals, ['addSetAside']);
    expect(p.messages.last.text, 'No problem, left it alone.');
    expect(p.errorMessage, isNull);
    p.dispose();
  });

  test('the loop stops at the hop ceiling and says it did not finish',
      () async {
    // A model that never stops asking for tools.
    scriptReplies([_toolTurn('findBills')]);
    final executor = _RecordingExecutor();
    final p = build(executor: executor);

    await p.send('sort out all my bills');

    // The last hop is spent on the ceiling message, so tools run one fewer
    // time than the ceiling allows.
    expect(executor.reads.length, AiCoachPresenter.maxToolHops - 1);
    expect(p.messages.last.text, contains("couldn't finish"));
    p.dispose();
  });

  test('a tool the catalogue does not contain is refused, not guessed at',
      () async {
    scriptReplies([
      _toolTurn('deleteEverything'),
      const AdvisorReply(text: 'I cannot do that.'),
    ]);
    final executor = _RecordingExecutor();
    final p = build(executor: executor);

    await p.send('delete everything');

    // Neither path is taken: an unknown name is not silently treated as a read.
    expect(executor.reads, isEmpty);
    expect(executor.proposals, isEmpty);
    expect(p.messages.last.text, 'I cannot do that.');
    p.dispose();
  });

  test('no tools are offered when nothing can execute them', () async {
    scriptReplies([const AdvisorReply(text: 'Here is my read.')]);
    final p = build(); // no executor

    await p.send('how am I doing?');

    // Declaring tools with no executor would let the model propose changes
    // that silently never happen.
    expect(capturedTools(), isEmpty);
    expect(p.messages.last.text, 'Here is my read.');
    p.dispose();
  });

  test('a running read names itself while the user waits', () async {
    // The gap this covers: the model has already written "let me check", so
    // the bubble's own thinking label is gone, and the next thing on screen is
    // a whole round trip away. Silence there reads as a hang.
    scriptReplies([
      _toolTurn('findBills', text: 'Let me look at your bills.'),
      const AdvisorReply(text: 'You have three due this week.'),
    ]);
    final executor = _RecordingExecutor();
    final p = build(executor: executor);
    String? statusDuringTool;
    executor.onCall = () => statusDuringTool = p.advisorStatus;

    await p.send('what bills do I have?');

    expect(statusDuringTool, 'Checking your bills…');
    // And it goes away with the turn, so nothing spins over a finished answer.
    expect(p.advisorStatus, isNull);
    p.dispose();
  });

  test('a pending proposal reports no status — the card speaks for itself',
      () async {
    scriptReplies([
      _toolTurn('addBill', text: 'Sure, adding that.'),
      const AdvisorReply(text: 'Done.'),
    ]);
    final executor = _RecordingExecutor();
    final p = build(executor: executor);
    String? statusDuringTool;
    executor.onCall = () => statusDuringTool = p.advisorStatus;

    await p.send('add my internet bill, 999, due the 15th');

    expect(executor.proposals, ['addBill']);
    // A spinner next to a card asking a question would be two things competing
    // to explain the same moment.
    expect(statusDuringTool, isNull);
    p.dispose();
  });

  test('tools are offered when an executor is present', () async {
    scriptReplies([const AdvisorReply(text: 'ok')]);
    final p = build(executor: _RecordingExecutor());

    await p.send('how am I doing?');

    final tools = capturedTools();
    expect(tools, isNotEmpty);
    expect(tools.map((t) => t.name), contains('addSetAside'));
    p.dispose();
  });
}
