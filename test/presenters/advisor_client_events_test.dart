import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_conversation.dart';
import 'package:intermittent_fasting/models/advisor_event.dart';
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
import 'package:intermittent_fasting/utils/advisor_client_events.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';
import '../support/recording_telemetry.dart';

/// Plan 065 phase 5: the advisor's client events. Each carries the trace id
/// of the message it belongs to, and counts or enum values only.

class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

/// A host whose batch the test answers by hand.
class _BatchExecutor extends ChangeNotifier
    implements FinanceToolExecutor, FinanceProposalHost {
  List<AiToolCall> _calls = const [];
  Completer<List<AiToolResult>>? _open;
  final Set<String> _removed = {};

  @override
  Future<AiToolResult> runRead(AiToolCall call) async =>
      AiToolResult(toolUseId: call.id, ok: true, summary: 'read');

  @override
  Future<AiToolResult> propose(AiToolCall call) async =>
      (await proposeBatch([call])).single;

  @override
  Future<List<AiToolResult>> proposeBatch(List<AiToolCall> calls) {
    _calls = calls;
    _removed.clear();
    _open = Completer();
    notifyListeners();
    return _open!.future;
  }

  void _finish(AiToolResult Function(AiToolCall c) r) {
    final open = _open;
    _open = null;
    open?.complete([
      for (final c in _calls)
        _removed.contains(c.id)
            ? AiToolResult(
                toolUseId: c.id,
                ok: false,
                summary: 'The user removed this change from the list, so it '
                    'was not saved.')
            : r(c),
    ]);
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
      toolUseId: c.id,
      ok: false,
      summary: 'Not approved, and nothing was saved. Instead of answering '
          'the card, the user wrote: "$userText".'));

  @override
  void removeAction(String callId) => _removed.add(callId);

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
  late RecordingTelemetry telemetry;
  late List<String?> traceIds;

  setUp(() {
    stats = MockStatsPresenter();
    fasting = MockFastingPresenter();
    service = MockAiCoachService();
    telemetry = RecordingTelemetry();
    traceIds = [];
    when(stats.stats).thenReturn(UserStats.initial());
    when(fasting.isFasting).thenReturn(false);
    when(fasting.fastingGoalHours).thenReturn(16);
    when(service.isAvailable).thenReturn(true);
    when(service.tier).thenReturn(AiCoachTier.cloud);
  });

  void scriptStreams(List<Stream<AdvisorEvent> Function()> script) {
    var i = 0;
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
      route: anyNamed('route'),
    )).thenAnswer((inv) {
      traceIds.add((inv.namedArguments[#context] as AiCoachContext).traceId);
      final next = script[i < script.length ? i : script.length - 1];
      i++;
      return next();
    });
  }

  void scriptReplies(List<AdvisorReply> script) =>
      scriptStreams([for (final r in script) () => advisorStreamOf(r)]);

  AiCoachPresenter build(_BatchExecutor executor,
      {MockStorageService? storage}) {
    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      storage: storage,
      imageCompressor: _PassthroughCompressor(),
      toolExecutor: executor,
      telemetry: telemetry,
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    return p;
  }

  test('an approved batch logs opened and answered, with the message trace',
      () async {
    scriptReplies([
      _step([('w1', 'addBill'), ('w2', 'addSetAside')]),
      const AdvisorReply(text: 'Both are saved.'),
    ]);
    final ex = _BatchExecutor();
    final p = build(ex);

    final turn = p.send('add internet and set aside for braces');
    await _settle();
    expect(telemetry.names, ['batch_opened']);
    expect(telemetry.named('batch_opened').fields, {'items': 2});

    await ex.approveAll();
    await turn;

    expect(telemetry.names, ['batch_opened', 'batch_answered']);
    expect(telemetry.named('batch_answered').fields, {
      'approved': 2,
      'declined': 0,
      'revised': 0,
      'removed': 0,
      'failed': 0,
    });
    final trace = traceIds.first;
    expect(trace, isNotNull);
    expect(telemetry.events.every((e) => e.traceId == trace), isTrue);
    p.dispose();
  });

  test('a removed row and a typed revision are counted apart', () async {
    scriptReplies([
      _step([('w1', 'addBill'), ('w2', 'addSetAside')]),
      const AdvisorReply(text: 'Got it.'),
    ]);
    final ex = _BatchExecutor();
    final p = build(ex);

    final turn = p.send('add internet and set aside for braces');
    await _settle();
    ex.removeAction('w2');
    await p.send('make the bill 2500');
    await turn;

    expect(telemetry.named('batch_answered').fields, {
      'approved': 0,
      'declined': 0,
      'revised': 1,
      'removed': 1,
      'failed': 0,
    });
    p.dispose();
  });

  test('stop while a batch is open logs phase batch, then a decline', () async {
    scriptReplies([
      _step([('w1', 'addBill')]),
    ]);
    final ex = _BatchExecutor();
    final p = build(ex);

    final turn = p.send('add my internet bill');
    await _settle();
    p.stop();
    await turn;

    expect(telemetry.names, ['batch_opened', 'stop_pressed', 'batch_answered']);
    expect(telemetry.named('stop_pressed').fields, {'phase': 'batch'});
    expect(telemetry.named('batch_answered').fields['declined'], 1);
    expect(telemetry.named('stop_pressed').traceId, traceIds.single);
    p.dispose();
  });

  test('stop mid-reply logs phase reply', () async {
    final hop = StreamController<AdvisorEvent>();
    scriptStreams([() => hop.stream]);
    final p = build(_BatchExecutor());

    final turn = p.send('plan my month');
    await _settle();
    hop
      ..add(const AdvisorEvent.start())
      ..add(const AdvisorEvent.delta('Start with rent'));
    await _settle();
    p.stop();
    await turn;

    expect(telemetry.names, ['stop_pressed']);
    expect(telemetry.events.single.fields, {'phase': 'reply'});
    expect(telemetry.events.single.traceId, traceIds.single);
    await hop.close();
    p.dispose();
  });

  test('a plain answer logs nothing', () async {
    scriptReplies([const AdvisorReply(text: 'You are on track.')]);
    final p = build(_BatchExecutor());

    await p.send('how am I doing?');

    expect(telemetry.events, isEmpty);
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
          'traceId': 'aabbccddeeff0011',
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

    test('a resumed batch logs "shown" and its answer with the saved trace',
        () async {
      when(storage.loadAdvisorOpenBatch())
          .thenAnswer((_) async => openBatch(DateTime.now()));
      scriptReplies([const AdvisorReply(text: 'Saved your internet bill.')]);
      final ex = _BatchExecutor();
      final p = build(ex, storage: storage);
      await _settle();

      expect(telemetry.names, ['batch_resumed']);
      expect(telemetry.events.single.fields, {'items': 1, 'outcome': 'shown'});
      expect(saved?['traceId'], 'aabbccddeeff0011',
          reason: 'the trace is saved again with the batch');

      await ex.approveAll();
      await _settle();

      expect(telemetry.names, ['batch_resumed', 'batch_answered']);
      expect(telemetry.events.every((e) => e.traceId == 'aabbccddeeff0011'),
          isTrue);
      p.dispose();
    });

    test('a batch too old to show logs "not_reviewed"', () async {
      when(storage.loadAdvisorOpenBatch()).thenAnswer((_) async =>
          openBatch(DateTime.now().subtract(const Duration(days: 2))));
      scriptReplies([const AdvisorReply(text: 'Nothing was saved.')]);
      final p = build(_BatchExecutor(), storage: storage);
      await _settle();

      expect(telemetry.names, ['batch_resumed']);
      expect(telemetry.events.single.fields,
          {'items': 1, 'outcome': 'not_reviewed'});
      expect(telemetry.events.single.traceId, 'aabbccddeeff0011');
      p.dispose();
    });
  });

  test('a batch saved during a turn carries the turn trace', () async {
    final storage = MockStorageService();
    final batches = <Map<String, dynamic>?>[];
    when(storage.loadAdvisorConversations()).thenAnswer((_) async => []);
    when(storage.loadAdvisorHistory()).thenAnswer((_) async => []);
    when(storage.loadAdvisorProfile()).thenAnswer((_) async => null);
    when(storage.loadAdvisorOpenBatch()).thenAnswer((_) async => null);
    when(storage.saveAdvisorConversations(any)).thenAnswer((_) async {});
    when(storage.saveAdvisorHistory(any)).thenAnswer((_) async {});
    when(storage.saveAdvisorOpenBatch(any)).thenAnswer((inv) async {
      batches.add(inv.positionalArguments.first as Map<String, dynamic>?);
    });
    scriptReplies([
      _step([('w1', 'addBill')]),
      const AdvisorReply(text: 'Saved.'),
    ]);
    final ex = _BatchExecutor();
    final p = build(ex, storage: storage);
    await _settle();

    final turn = p.send('add my internet bill');
    await _settle();
    await ex.approveAll();
    await turn;

    expect(batches.whereType<Map<String, dynamic>>().first['traceId'],
        traceIds.first);
    p.dispose();
  });

  group('batchOutcomeCounts', () {
    test('sorts each result by its summary', () {
      final counts = batchOutcomeCounts([
        const AiToolResult(toolUseId: 'a', ok: true, summary: 'Saved.'),
        AiToolResult.declined('b'),
        const AiToolResult(
            toolUseId: 'c',
            ok: false,
            summary: 'Not approved, and nothing was saved. Instead of '
                'answering the card, the user wrote: "x".'),
        const AiToolResult(
            toolUseId: 'd',
            ok: false,
            summary: 'The user removed this change from the list, so it was '
                'not saved.'),
        const AiToolResult(
            toolUseId: 'e',
            ok: false,
            summary: 'Not saved: it used the new category "Pets", which the '
                'user removed.'),
        AiToolResult.failed('f', 'Saving that failed, so nothing was changed.'),
      ]);

      expect(counts, {
        'approved': 1,
        'declined': 1,
        'revised': 1,
        'removed': 2,
        'failed': 1,
      });
    });
  });

  group('CloudAiCoachService.eventBody', () {
    test('is op logEvent with the name, trace and fields', () {
      expect(
        CloudAiCoachService.eventBody(AdvisorClientEvent.batchOpened,
            traceId: 't1', fields: {'items': 2}),
        {
          'op': 'logEvent',
          'payload': {
            'event': 'batch_opened',
            'trace_id': 't1',
            'fields': {'items': 2},
          },
        },
      );
    });

    test('leaves out a missing trace and empty fields', () {
      expect(CloudAiCoachService.eventBody(AdvisorClientEvent.askNudgyTapped), {
        'op': 'logEvent',
        'payload': {'event': 'ask_nudgy_tapped'},
      });
    });

    test('does nothing without a transport', () {
      // No AI_COACH_ENDPOINT in a test build: record returns at once and
      // sends nothing.
      CloudAiCoachService(tokenProvider: () => 'token')
          .record(AdvisorClientEvent.askNudgyTapped);
    });
  });
}
