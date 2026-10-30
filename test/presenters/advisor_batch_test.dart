import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_conversation.dart';
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

/// Plan 065 phase 4: every write of one step is one batch; typing while it is
/// open answers it; it survives an app restart.

class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

/// A host whose batch the test answers by hand.
class _BatchExecutor extends ChangeNotifier
    implements FinanceToolExecutor, FinanceProposalHost {
  final List<List<String>> batches = [];
  final List<String> reads = [];
  List<AiToolCall> _calls = const [];
  Completer<List<AiToolResult>>? _open;

  @override
  Future<AiToolResult> runRead(AiToolCall call) async {
    reads.add(call.name);
    return AiToolResult(toolUseId: call.id, ok: true, summary: 'read');
  }

  @override
  Future<AiToolResult> propose(AiToolCall call) async =>
      (await proposeBatch([call])).single;

  @override
  Future<List<AiToolResult>> proposeBatch(List<AiToolCall> calls) {
    batches.add([for (final c in calls) c.name]);
    _calls = calls;
    _open = Completer();
    notifyListeners();
    return _open!.future;
  }

  void _finish(AiToolResult Function(AiToolCall c) r) {
    final open = _open;
    _open = null;
    open?.complete([for (final c in _calls) r(c)]);
    notifyListeners();
  }

  @override
  PendingBatch? get batch => _open == null
      ? null
      : PendingBatch(id: 'b', actions: [
          for (final c in _calls)
            PendingFinanceAction(
                call: c, title: c.name, details: const [], isRecurring: false),
        ]);

  @override
  PendingFinanceAction? get pending => batch?.actions.first;

  @override
  bool get batchHasLedgerRows => false;

  @override
  int get openRowCount => _calls.length;

  @override
  bool get canApproveAll => true;

  @override
  Future<void> approveAll({
    Map<String, bool> applyToFuture = const {},
    Map<String, bool> alreadyLogged = const {},
  }) async =>
      _finish((c) => AiToolResult(toolUseId: c.id, ok: true, summary: 'saved'));

  @override
  Future<void> confirm({bool applyToFuture = false, bool? alreadyLogged}) =>
      approveAll();

  @override
  void decline() => _finish((c) => AiToolResult.declined(c.id));

  @override
  void reviseAll(String userText) => _finish((c) => AiToolResult(
      toolUseId: c.id, ok: false, summary: 'not approved: $userText'));

  @override
  void removeAction(String callId) {}

  @override
  String? editAction(String callId, Map<String, Object?> patch) => null;
}

AdvisorReply _step(List<(String id, String name)> calls) => AdvisorReply(
      text: 'Here is what I would change.',
      toolCalls: [
        for (final c in calls)
          AiToolCall(id: c.$1, name: c.$2, input: const {}),
      ],
      assistantContent: [
        for (final c in calls)
          {'type': 'tool_use', 'id': c.$1, 'name': c.$2, 'input': {}},
      ],
    );

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MockStatsPresenter stats;
  late MockFastingPresenter fasting;
  late MockAiCoachService service;
  late List<List<AiChatMessage>> requests;

  setUp(() {
    stats = MockStatsPresenter();
    fasting = MockFastingPresenter();
    service = MockAiCoachService();
    requests = [];
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
    )).thenAnswer((inv) {
      requests
          .add(List.of(inv.namedArguments[#messages] as List<AiChatMessage>));
      final reply = script[i < script.length ? i : script.length - 1];
      i++;
      return advisorStreamOf(reply);
    });
  }

  AiCoachPresenter build(_BatchExecutor executor,
      {MockStorageService? storage}) {
    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      storage: storage,
      imageCompressor: _PassthroughCompressor(),
      toolExecutor: executor,
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    return p;
  }

  test('every write of one step is one batch; reads run first', () async {
    scriptReplies([
      _step([('r1', 'find'), ('w1', 'addBill'), ('w2', 'addSetAside')]),
      const AdvisorReply(text: 'Both are saved.'),
    ]);
    final ex = _BatchExecutor();
    final p = build(ex);

    final turn = p.send('add internet and set aside for braces');
    await _settle();
    expect(ex.reads, ['find']);
    expect(ex.batches, [
      ['addBill', 'addSetAside']
    ]);
    expect(p.isAwaitingBatch, isTrue);
    expect(p.canType, isTrue, reason: 'a typed reply can answer the batch');

    await ex.approveAll();
    await turn;

    // One tool_result per tool_use, in call order, in one user turn.
    final results = requests.last.last.contentBlocks;
    expect([for (final b in results) b['tool_use_id']], ['r1', 'w1', 'w2']);
    expect(p.messages.last.text, 'Both are saved.');
    p.dispose();
  });

  test('typing while the batch is open answers it with the user\'s words',
      () async {
    scriptReplies([
      _step([('w1', 'addBill')]),
      const AdvisorReply(text: 'Got it, ₱2,500 then.'),
    ]);
    final ex = _BatchExecutor();
    final p = build(ex);

    final turn = p.send('add my internet bill');
    await _settle();
    expect(p.isAwaitingBatch, isTrue);

    await p.send('make it 2500 instead');
    await turn;

    final last = requests.last.last.contentBlocks;
    expect(last.first['type'], 'tool_result');
    expect(last.first['content'].toString(), contains('not approved'));
    // The user's words ride in the same user turn as the results.
    expect(last.last, {'type': 'text', 'text': 'make it 2500 instead'});
    expect(p.messages.map((m) => m.text),
        containsAllInOrder(['make it 2500 instead', 'Got it, ₱2,500 then.']));
    p.dispose();
  });

  group('after an app restart', () {
    late MockStorageService storage;
    Map<String, dynamic>? saved;

    setUp(() {
      storage = MockStorageService();
      saved = null;
      final now = DateTime.now();
      when(storage.loadAdvisorConversations()).thenAnswer((_) async => [
            AdvisorConversation(
              id: 'c1',
              title: 'Bills',
              createdAt: now,
              updatedAt: now,
              messages: [AiChatMessage.user('add my internet bill')],
            ),
          ]);
      when(storage.loadAdvisorProfile()).thenAnswer((_) async => null);
      when(storage.saveAdvisorConversations(any)).thenAnswer((_) async {});
      when(storage.saveAdvisorHistory(any)).thenAnswer((_) async {});
      when(storage.saveAdvisorOpenBatch(any)).thenAnswer((inv) async {
        saved = inv.positionalArguments.first as Map<String, dynamic>?;
      });
    });

    Map<String, dynamic> openBatch(DateTime savedAt) => {
          'conversationId': 'c1',
          'savedAt': savedAt.toIso8601String(),
          'transcript': [
            AiChatMessage.user('add my internet bill').toJson(),
            AiChatMessage.assistantToolUse(text: 'Here it is.', contentBlocks: [
              {'type': 'tool_use', 'id': 'w1', 'name': 'addBill', 'input': {}},
            ]).toJson(),
          ],
          'calls': [
            {'id': 'w1', 'name': 'addBill', 'input': <String, Object?>{}},
          ],
        };

    test('the batch is shown again and the answer finishes the turn', () async {
      when(storage.loadAdvisorOpenBatch())
          .thenAnswer((_) async => openBatch(DateTime.now()));
      scriptReplies([const AdvisorReply(text: 'Saved your internet bill.')]);
      final ex = _BatchExecutor();
      final p = build(ex, storage: storage);
      await _settle();

      expect(ex.batches, [
        ['addBill']
      ]);
      expect(p.isAwaitingBatch, isTrue);

      await ex.approveAll();
      await _settle();

      final req = requests.single;
      expect(req.last.contentBlocks.single['tool_use_id'], 'w1');
      expect(p.messages.last.text, 'Saved your internet bill.');
      expect(saved, isNull, reason: 'an answered batch is cleared');
      p.dispose();
    });

    test('a batch too old to show is answered "not reviewed"', () async {
      when(storage.loadAdvisorOpenBatch()).thenAnswer((_) async =>
          openBatch(DateTime.now().subtract(const Duration(days: 2))));
      scriptReplies([const AdvisorReply(text: 'Nothing was saved.')]);
      final ex = _BatchExecutor();
      final p = build(ex, storage: storage);
      await _settle();

      expect(ex.batches, isEmpty);
      final block = requests.single.last.contentBlocks.single;
      expect(block['tool_use_id'], 'w1');
      expect(block['content'].toString(), contains('Not reviewed'));
      p.dispose();
    });
  });
}
