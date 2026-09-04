import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';

/// Guards the two invariants the catalogue exists to hold, plus the MCP
/// mapping. These are cheap assertions over data, but they are the ones that
/// stop a later "just add one more field" from quietly handing the model a
/// destructive lever.
void main() {
  Iterable<Object?> schemaKeysDeep(Object? node) sync* {
    if (node is Map) {
      for (final entry in node.entries) {
        yield entry.key;
        yield* schemaKeysDeep(entry.value);
      }
    } else if (node is List) {
      for (final item in node) {
        yield* schemaKeysDeep(item);
      }
    }
  }

  group('catalogue invariants', () {
    test('no schema exposes applyToFuture', () {
      // Recurrence scope is the user's choice on the confirm card. On a delete
      // it is the difference between removing one row and erasing a series
      // across every future month, so the model must not be able to set it.
      for (final tool in kFinanceTools) {
        final keys = schemaKeysDeep(tool.inputSchema).map((k) => '$k');
        expect(keys, isNot(contains('applyToFuture')),
            reason: '${tool.name} exposes recurrence scope to the model');
      }
    });

    test('no create tool accepts an entity id', () {
      // The model cannot see ids, so an id on a create is necessarily invented.
      for (final tool
          in kFinanceTools.where((t) => t.kind == AiToolKind.create)) {
        final props = (tool.inputSchema['properties'] as Map?) ??
            const <String, Object?>{};
        expect(props.keys.map((k) => '$k'), isNot(contains('id')),
            reason: '${tool.name} takes an id but creates a new row');
      }
    });

    test('every tool has a unique name and a non-empty description', () {
      final names = kFinanceTools.map((t) => t.name).toList();
      expect(names.toSet().length, names.length, reason: 'duplicate tool name');
      for (final tool in kFinanceTools) {
        expect(tool.description.trim(), isNotEmpty);
      }
    });

    test('reads do not mutate, writes do', () {
      for (final tool in kFinanceTools) {
        expect(tool.mutates, tool.kind != AiToolKind.read,
            reason: '${tool.name} disagrees with its kind');
      }
      // Phase 1 ships creates and reads only; edit and delete come later.
      expect(kFinanceTools.map((t) => t.kind).toSet(),
          {AiToolKind.read, AiToolKind.create});
    });

    test('lookup resolves a real name and rejects an invented one', () {
      expect(financeToolNamed('addSetAside')?.name, 'addSetAside');
      expect(financeToolNamed('deleteEverything'), isNull);
    });
  });

  group('MCP mapping', () {
    test('both serialisations agree on name, description and schema', () {
      final bedrock = financeToolsRequestJson();
      final mcp = financeToolsMcpJson();
      expect(bedrock.length, kFinanceTools.length);
      expect(mcp.length, kFinanceTools.length);

      for (var i = 0; i < kFinanceTools.length; i++) {
        expect(mcp[i]['name'], bedrock[i]['name']);
        expect(mcp[i]['description'], bedrock[i]['description']);
        // The key differs by casing between the two protocols; the schema
        // behind it must not.
        expect(mcp[i]['inputSchema'], bedrock[i]['input_schema']);
      }
    });

    test('annotations follow the tool kind', () {
      const read = AiToolKind.read;
      const create = AiToolKind.create;
      const update = AiToolKind.update;
      const destroy = AiToolKind.destroy;

      expect(read.readOnlyHint, isTrue);
      expect(read.destructiveHint, isFalse);
      expect(read.idempotentHint, isTrue);

      // A create run twice leaves two rows, so it is not idempotent.
      expect(create.idempotentHint, isFalse);
      expect(create.destructiveHint, isFalse);

      expect(update.idempotentHint, isTrue);
      expect(update.destructiveHint, isFalse);

      expect(destroy.destructiveHint, isTrue);
      expect(destroy.readOnlyHint, isFalse);
    });

    test('a declined result is an error to the model, not a success', () {
      final declined = AiToolResult.declined('tu_1');
      expect(declined.ok, isFalse);
      expect(declined.toContentBlock()['is_error'], isTrue);
      expect(declined.toMcpJson()['isError'], isTrue);
      // The model must be told not to simply try again.
      expect(declined.summary, contains('declined'));
      expect(declined.summary.toLowerCase(), contains('do not'));
    });

    test('a tool result echoes the call id it answers', () {
      const result =
          AiToolResult(toolUseId: 'tu_42', ok: true, summary: 'Saved.');
      expect(result.toContentBlock()['tool_use_id'], 'tu_42');
      // A successful result carries no error flag at all.
      expect(result.toContentBlock().containsKey('is_error'), isFalse);
      expect(result.toMcpJson()['isError'], isFalse);
    });

    test('a tool call round-trips through json', () {
      const call = AiToolCall(
          id: 'tu_1', name: 'addSetAside', input: {'name': 'Braces'});
      final back = AiToolCall.fromJson(call.toJson());
      expect(back.id, call.id);
      expect(back.name, call.name);
      expect(back.input, call.input);
    });
  });
}
