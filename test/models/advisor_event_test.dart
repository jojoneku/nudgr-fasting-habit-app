import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_event.dart';

/// The advisor's wire protocol. These are frames as the Lambda actually emits
/// them, so a change on either side that breaks the pairing fails here.
void main() {
  AdvisorEvent parse(String line) =>
      AdvisorEvent.fromJson(jsonDecode(line) as Map<String, Object?>);

  group('frame parsing', () {
    test('start', () {
      final e = parse('{"type":"start"}');
      expect(e.kind, AdvisorEventKind.start);
      expect(e.isTerminal, isFalse);
    });

    test('delta carries its text', () {
      final e = parse('{"type":"delta","text":"You are at "}');
      expect(e.kind, AdvisorEventKind.delta);
      expect(e.text, 'You are at ');
      expect(e.isTerminal, isFalse);
    });

    test('end carries the reply, parsed by AdvisorReply', () {
      final e = parse('{"type":"end","response":"Cut delivery first.",'
          '"truncated":false,"tool_calls":[],"assistant_content":'
          '[{"type":"text","text":"Cut delivery first."}]}');
      expect(e.kind, AdvisorEventKind.end);
      expect(e.isTerminal, isTrue);
      expect(e.reply!.text, 'Cut delivery first.');
      expect(e.reply!.wantsTools, isFalse);
      expect(e.reply!.assistantContent, hasLength(1));
    });

    test('end with tool calls keeps the ids the results pair with', () {
      final e = parse('{"type":"end","response":"","truncated":false,'
          '"tool_calls":[{"id":"toolu_1","name":"create_set_aside",'
          '"input":{"amount":1500,"pocket":"Emergency Fund"}}],'
          '"assistant_content":[{"type":"tool_use","id":"toolu_1",'
          '"name":"create_set_aside","input":{"amount":1500}}]}');
      expect(e.reply!.wantsTools, isTrue);
      expect(e.reply!.toolCalls.single.id, 'toolu_1');
      expect(e.reply!.toolCalls.single.name, 'create_set_aside');
      expect(e.reply!.toolCalls.single.input['pocket'], 'Emergency Fund');
      // Verbatim, because a rebuilt turn loses the tool_use id.
      expect(e.reply!.assistantContent.single['id'], 'toolu_1');
    });

    test('end reports truncation rather than leaving it to be inferred', () {
      final e = parse('{"type":"end","response":"...","truncated":true,'
          '"tool_calls":[],"assistant_content":[]}');
      expect(e.reply!.truncated, isTrue);
    });

    test('error is terminal and carries its message', () {
      final e = parse('{"type":"error","message":"Bedrock fell over."}');
      expect(e.kind, AdvisorEventKind.error);
      expect(e.isTerminal, isTrue);
      expect(e.message, 'Bedrock fell over.');
    });

    test('error without a message still says something usable', () {
      final e = parse('{"type":"error"}');
      expect(e.message, isNotEmpty);
    });

    test('an unknown frame type is an error, not silently ignored', () {
      // Client and server disagreeing about the protocol must not produce a
      // reply that quietly omits whatever the new frame carried.
      final e = parse('{"type":"reasoning","text":"hmm"}');
      expect(e.kind, AdvisorEventKind.error);
      expect(e.isTerminal, isTrue);
    });
  });

  group('the terminator contract', () {
    test('only end and error terminate a turn', () {
      expect(const AdvisorEvent.start().isTerminal, isFalse);
      expect(const AdvisorEvent.delta('x').isTerminal, isFalse);
      expect(parse('{"type":"end","response":"a"}').isTerminal, isTrue);
      expect(parse('{"type":"error","message":"b"}').isTerminal, isTrue);
    });
  });
}
