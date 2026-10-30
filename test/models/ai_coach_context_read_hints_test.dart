import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/services/cloud_ai_coach_service.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';

/// The read hints in the finance snapshot (Plan 066).
///
/// A snapshot line that only summarises a record reads as the whole record, so
/// the advisor answered "I can't see that" about a field `find` returns. Each
/// section that names records now ends with a hint naming the read tool — but
/// only for a request that sends the tools.
void main() {
  const ctx = AiCoachContext(
    entryPoint: AiCoachEntryPoint.financeAdvisor,
    liquidAccounts: [AdvisorAccountLine(name: 'GCash', balance: 6420)],
    budgetGroups: [
      AdvisorBudgetGroupLine(name: 'Wants', allocated: 11500, spent: 6850),
    ],
    setAsides: [
      AdvisorSetAsideLine(
          name: 'Christmas gifts',
          allocated: 2000,
          funded: 0,
          remaining: 2000,
          isFunded: false),
    ],
    goals: [AdvisorGoalLine(name: 'Japan trip', saved: 55000, target: 90000)],
    creditLines: [AdvisorCreditLine(name: 'BPI Credit Card', owed: 18740)],
    installments: [
      AdvisorInstallmentLine(
          name: 'Panasonic Refrigerator',
          monthlyAmount: 2499,
          remainingMonths: 12,
          remainingAmount: 29988),
    ],
    paidBillsThisMonth: [AdvisorBillLine(name: 'Netflix', amount: 549)],
    pendingReceivables: [
      AdvisorReceivableLine(name: 'Salary (2nd half)', amount: 42500),
    ],
    topCategories: [
      AdvisorCategoryLine(name: 'Groceries', target: 8000, actual: 6820),
    ],
    recentTransactions: [
      AdvisorTxnLine(
          dateLabel: 'Oct 15',
          description: 'Starbucks',
          amount: 240,
          category: 'Food & Dining'),
    ],
  );

  List<String> hints(String s) =>
      s.split('\n').where((l) => l.contains('(Summary only.')).toList();

  test('off by default: the snapshot carries no read hints', () {
    expect(hints(ctx.financeSnapshotSummary()), isEmpty);
  });

  test('each section that names records ends with its read tool', () {
    final s = ctx.financeSnapshotSummary(readHints: true);

    for (final call in [
      'find (entity account)',
      'find (entity budgetGroup)',
      'find (entity setAside)',
      'find (entity installment)',
      'find (entity bill)',
      'find (entity receivable)',
      'find (entity budget)',
      'findTransactions',
    ]) {
      expect(hints(s).where((h) => h.contains(call)), isNotEmpty, reason: call);
    }
    // The hint follows its own section: the plan line, then the hint.
    final lines = s.split('\n');
    final plan = lines.indexWhere((l) => l.contains('Panasonic Refrigerator'));
    expect(lines[plan + 1], contains('find (entity installment)'));
    expect(lines[plan + 1], contains('deferral'));
  });

  test('a section with no records gets no hint', () {
    const empty = AiCoachContext(
      entryPoint: AiCoachEntryPoint.financeAdvisor,
      totalLiquidCash: 1000,
    );
    expect(hints(empty.financeSnapshotSummary(readHints: true)), isEmpty);
  });

  group('advisorPayload', () {
    String summary(List<AiTool> tools) {
      final payload = CloudAiCoachService.advisorPayload(
        messages: [AiChatMessage.user('When does the fridge plan start?')],
        context: ctx,
        tools: tools,
      );
      return (payload['context']! as Map)['summary'] as String;
    }

    test('sends the hints with the tools they point at', () {
      expect(hints(summary(kFinanceTools)), isNotEmpty);
    });

    test('sends none without tools', () {
      expect(hints(summary(const [])), isEmpty);
    });
  });
}
