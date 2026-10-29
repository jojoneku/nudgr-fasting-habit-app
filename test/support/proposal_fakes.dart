import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';

/// Gives a test executor that only knows [propose] the batch API: each call
/// of a batch is proposed in turn, the way the loop used to run them.
mixin ProposeBatchOneByOne {
  Future<AiToolResult> propose(AiToolCall call);

  Future<List<AiToolResult>> proposeBatch(List<AiToolCall> calls) async =>
      [for (final c in calls) await propose(c)];
}

/// Gives a single-proposal test host the batch API: its one pending
/// proposal is a batch of one.
mixin SingleProposalBatch {
  PendingFinanceAction? get pending;
  Future<void> confirm({bool applyToFuture = false, bool? alreadyLogged});
  void decline();

  bool get batchHasLedgerRows => false;

  int get openRowCount => pending == null ? 0 : 1;

  bool get canApproveAll => true;

  PendingBatch? get batch {
    final p = pending;
    return p == null ? null : PendingBatch(id: 'b_${p.call.id}', actions: [p]);
  }

  Future<void> approveAll({
    Map<String, bool> applyToFuture = const {},
    Map<String, bool> alreadyLogged = const {},
  }) {
    final id = pending?.call.id;
    return confirm(
      applyToFuture: applyToFuture[id] ?? false,
      alreadyLogged: alreadyLogged[id],
    );
  }

  void removeAction(String callId) => decline();

  String? editAction(String callId, Map<String, Object?> patch) => null;

  void reviseAll(String userText) => decline();
}
