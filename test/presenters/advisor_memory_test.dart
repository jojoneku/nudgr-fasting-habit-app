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
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';

/// Plan 065 phase 5: a new conversation after a long idle gap, and a request
/// trimmed in chunks while the saved thread keeps every message.

/// A host whose batch the test answers by hand.
class _BatchExecutor extends ChangeNotifier
    implements FinanceToolExecutor, FinanceProposalHost {
  List<AiToolCall> _calls = const [];
  Completer<List<AiToolResult>>? _open;

  @override
  Future<AiToolResult> runRead(AiToolCall call) async =>
      AiToolResult(toolUseId: call.id, ok: true, summary: 'read');

  @override
  Future<AiToolResult> propose(AiToolCall call) async =>
      (await proposeBatch([call])).single;

  @override
  Future<List<AiToolResult>> proposeBatch(List<AiToolCall> calls) {
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

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

AiChatMessage _msg(int i, AiChatRole role, {DateTime? at}) => AiChatMessage(
      id: 'm$i',
      role: role,
      text: '${role.name} $i',
      timestamp: at ?? DateTime(2026, 10, 30, 9),
    );

/// [count] messages that alternate user, assistant, starting with a user.
List<AiChatMessage> _pairs(int count, {int offset = 0, DateTime? at}) => [
      for (var i = 0; i < count; i++)
        _msg(i + offset, i.isEven ? AiChatRole.user : AiChatRole.assistant,
            at: at),
    ];

void main() {
  group('trimForRequest', () {
    const threshold = AiCoachPresenter.requestTrimThreshold;
    const chunk = AiCoachPresenter.requestTrimChunk;

    test('sends everything up to the threshold', () {
      final all = _pairs(threshold);
      expect(AiCoachPresenter.trimForRequest(all), all);
    });

    test('drops the oldest chunk once the threshold is passed', () {
      final all = _pairs(threshold + 1);
      final sent = AiCoachPresenter.trimForRequest(all);
      expect(sent, all.sublist(chunk));
      expect(sent.first.role, AiChatRole.user);
    });

    test('drops a second chunk only after a second chunk of growth', () {
      expect(AiCoachPresenter.trimForRequest(_pairs(threshold + chunk)).length,
          threshold);
      expect(
          AiCoachPresenter.trimForRequest(_pairs(threshold + chunk + 1)).length,
          threshold + 1 - chunk);
    });

    test('a cut on a reply moves past it, so a pair is never split', () {
      // A user message the ledger handled, with no reply, shifts every pair
      // by one, so the chunk boundary lands on an assistant reply.
      final all = [
        _msg(0, AiChatRole.user),
        ..._pairs(threshold, offset: 1),
      ];
      expect(all[chunk].role, AiChatRole.assistant);

      final sent = AiCoachPresenter.trimForRequest(all);
      expect(sent, all.sublist(chunk + 1));
      expect(sent.first.role, AiChatRole.user);
      expect(sent[1].role, AiChatRole.assistant);
    });

    test('the request start stays the same between chunk boundaries', () {
      final all = _pairs(threshold + 2 * chunk + 1);
      List<AiChatMessage> sentAt(int n) =>
          AiCoachPresenter.trimForRequest(all.sublist(0, n));

      for (var n = threshold + 1; n < threshold + chunk; n++) {
        final now = sentAt(n);
        final next = sentAt(n + 1);
        // Each request is the previous one plus the new messages: the cached
        // prefix is still a prefix.
        expect(next.sublist(0, now.length), now, reason: 'n=$n');
      }
      // The next trim moves the start once, by a whole chunk.
      expect(sentAt(threshold + chunk + 1).first.id,
          isNot(sentAt(threshold + chunk).first.id));
    });
  });

  group('with a presenter', () {
    late MockStatsPresenter stats;
    late MockFastingPresenter fasting;
    late MockAiCoachService service;
    late MockStorageService storage;
    late List<List<AiChatMessage>> requests;
    late List<AdvisorConversation> stored;
    late List<AdvisorConversation> lastSaved;
    late DateTime now;

    setUp(() {
      stats = MockStatsPresenter();
      fasting = MockFastingPresenter();
      service = MockAiCoachService();
      storage = MockStorageService();
      requests = [];
      stored = [];
      lastSaved = [];
      now = DateTime.now();
      when(stats.stats).thenReturn(UserStats.initial());
      when(fasting.isFasting).thenReturn(false);
      when(fasting.fastingGoalHours).thenReturn(16);
      when(service.isAvailable).thenReturn(true);
      when(service.tier).thenReturn(AiCoachTier.cloud);
      when(storage.loadAdvisorConversations()).thenAnswer((_) async => stored);
      when(storage.loadAdvisorProfile()).thenAnswer((_) async => null);
      when(storage.loadAdvisorOpenBatch()).thenAnswer((_) async => null);
      when(storage.saveAdvisorConversations(any)).thenAnswer((inv) async {
        lastSaved =
            List.of(inv.positionalArguments.first as List<AdvisorConversation>);
      });
      when(storage.saveAdvisorHistory(any)).thenAnswer((_) async {});
      when(storage.saveAdvisorOpenBatch(any)).thenAnswer((_) async {});
    });

    void scriptReplies(List<AdvisorReply> script) {
      var i = 0;
      when(service.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        tools: anyNamed('tools'),
      )).thenAnswer((inv) {
        requests
            .add(List.of(inv.namedArguments[#messages] as List<AiChatMessage>));
        final reply = script[i < script.length ? i : script.length - 1];
        i++;
        return advisorStreamOf(reply);
      });
    }

    AdvisorConversation convo(String id, List<AiChatMessage> messages) =>
        AdvisorConversation(
          id: id,
          title: id,
          createdAt: messages.first.timestamp,
          updatedAt: messages.last.timestamp,
          messages: messages,
        );

    Future<AiCoachPresenter> open({
      bool withStorage = true,
      FinanceToolExecutor? executor,
    }) async {
      final p = AiCoachPresenter(
        stats: stats,
        fasting: fasting,
        service: service,
        storage: withStorage ? storage : null,
        toolExecutor: executor,
        clock: () => now,
      );
      p.openSession(AiCoachEntryPoint.financeAdvisor);
      await _settle();
      return p;
    }

    test('a message after a long silence starts a new conversation', () async {
      final old = _pairs(4, at: now.subtract(const Duration(hours: 7)));
      stored = [convo('c1', old)];
      scriptReplies([const AdvisorReply(text: 'Hello again.')]);
      final p = await open();

      expect(p.startsFreshAfterIdleGap, isTrue);
      await p.send('how are my bills?');

      expect(p.currentConversationId, isNot('c1'));
      expect(
          p.messages.map((m) => m.text), ['how are my bills?', 'Hello again.']);
      // The new chat sends none of the old one.
      expect(requests.single.map((m) => m.text), ['how are my bills?']);
      // The old chat is still in the list, unchanged.
      final kept = p.conversations.firstWhere((c) => c.id == 'c1');
      expect(kept.messages.map((m) => m.id), old.map((m) => m.id));
      p.dispose();
    });

    test('a message inside the gap stays in the same conversation', () async {
      stored = [
        convo('c1', _pairs(4, at: now.subtract(const Duration(hours: 5))))
      ];
      scriptReplies([const AdvisorReply(text: 'Sure.')]);
      final p = await open();

      expect(p.startsFreshAfterIdleGap, isFalse);
      await p.send('and the internet one?');

      expect(p.currentConversationId, 'c1');
      expect(requests.single, hasLength(5));
      p.dispose();
    });

    test('an old chat the user picks from the list stays open', () async {
      stored = [
        convo('c1', _pairs(4, at: now.subtract(const Duration(days: 3)))),
        convo('c2', _pairs(2, offset: 10, at: now)),
      ];
      scriptReplies([const AdvisorReply(text: 'Picking up from there.')]);
      final p = await open();
      expect(p.currentConversationId, 'c2');

      p.openConversation('c1');
      expect(p.startsFreshAfterIdleGap, isFalse);
      await p.send('about that plan');

      expect(p.currentConversationId, 'c1');
      expect(requests.single, hasLength(5));
      p.dispose();
    });

    test('not while a turn is running', () async {
      final reply = StreamController<AdvisorEvent>();
      when(service.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        tools: anyNamed('tools'),
      )).thenAnswer((_) => reply.stream);
      final p = await open();
      final id = p.currentConversationId;

      final turn = p.send('first question');
      await _settle();
      now = now.add(const Duration(hours: 7));
      expect(p.isResponding, isTrue);
      expect(p.startsFreshAfterIdleGap, isFalse);

      reply
        ..add(const AdvisorEvent.start())
        ..add(const AdvisorEvent.end(AdvisorReply(text: 'An answer.')))
        ..close();
      await turn;
      expect(p.currentConversationId, id);
      // Once the turn is over the silence counts again.
      expect(p.startsFreshAfterIdleGap, isTrue);
      p.dispose();
    });

    test('not while a batch of changes waits for the user', () async {
      scriptReplies([
        const AdvisorReply(
          text: 'Here is what I would change.',
          toolCalls: [AiToolCall(id: 'w1', name: 'addBill', input: {})],
          assistantContent: [
            {'type': 'tool_use', 'id': 'w1', 'name': 'addBill', 'input': {}},
          ],
        ),
        const AdvisorReply(text: 'Got it, ₱2,500 then.'),
      ]);
      final p = await open(executor: _BatchExecutor());
      final id = p.currentConversationId;

      final turn = p.send('add my internet bill');
      await _settle();
      expect(p.isAwaitingBatch, isTrue);
      now = now.add(const Duration(hours: 7));
      expect(p.startsFreshAfterIdleGap, isFalse);

      await p.send('make it 2500 instead');
      await turn;

      expect(p.currentConversationId, id);
      expect(requests.last.last.contentBlocks.first['content'].toString(),
          contains('not approved'));
      p.dispose();
    });

    test('not while a saved batch is being read back', () async {
      stored = [
        convo('c1', _pairs(2, at: now.subtract(const Duration(hours: 7))))
      ];
      final saved = Completer<Map<String, dynamic>?>();
      when(storage.loadAdvisorOpenBatch()).thenAnswer((_) => saved.future);
      final p = await open();

      expect(p.currentConversationId, 'c1');
      expect(p.startsFreshAfterIdleGap, isFalse);

      saved.complete(null);
      await _settle();
      expect(p.startsFreshAfterIdleGap, isTrue);
      p.dispose();
    });

    test('never for the other coaches', () async {
      when(service.respond(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        isThinking: anyNamed('isThinking'),
      )).thenAnswer((_) => Stream.fromIterable(['Keep going.']));
      final p = AiCoachPresenter(
        stats: stats,
        fasting: fasting,
        service: service,
        clock: () => now,
      );
      await p.send('status?');
      now = now.add(const Duration(days: 1));

      expect(p.startsFreshAfterIdleGap, isFalse);
      p.dispose();
    });

    test('a long chat sends a trimmed request but keeps every message',
        () async {
      final long = _pairs(60, at: now);
      stored = [convo('c1', long)];
      scriptReplies([const AdvisorReply(text: 'Reply 61.')]);
      final p = await open();

      await p.send('question 61');

      final sent = requests.single;
      expect(sent, hasLength(61 - AiCoachPresenter.requestTrimChunk));
      expect(sent.first.id, long[AiCoachPresenter.requestTrimChunk].id);
      expect(sent.last.text, 'question 61');
      // On screen and in storage, nothing is dropped.
      expect(p.messages, hasLength(62));
      expect(p.messages.first.id, long.first.id);
      final saved = lastSaved.firstWhere((c) => c.id == 'c1');
      expect(saved.messages, hasLength(62));
      p.dispose();
    });

    test('the request start holds across turns until the next chunk', () async {
      stored = [convo('c1', _pairs(52, at: now))];
      scriptReplies([const AdvisorReply(text: 'ok')]);
      final p = await open();

      await p.send('one');
      await p.send('two');

      // 53 then 55 messages sent: both trimmed by the same one chunk.
      expect(requests, hasLength(2));
      expect(requests[0].first.id, requests[1].first.id);
      expect(requests[1].sublist(0, requests[0].length).map((m) => m.id),
          requests[0].map((m) => m.id));
      p.dispose();
    });
  });
}
