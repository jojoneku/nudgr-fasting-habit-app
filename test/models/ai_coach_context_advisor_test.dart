import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';

void main() {
  group('AiCoachContext.financeSnapshotSummary', () {
    test('renders PHP-formatted figures with thousands separators', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        totalLiquidCash: 42350.75,
        forecastedNetBalance: 12800,
        netWorth: 1234567,
        monthNetCashFlow: -5400,
        savingsRatePct: 18,
        monthBudget: 20000,
        monthSpent: 15250,
        totalCreditOwed: 3000,
        totalCreditAvailable: 47000,
        daysLeftInMonth: 9,
        outstandingBillsTotal: 4200,
        outstandingBills: [
          AdvisorBillLine(name: 'Internet', amount: 1699),
          AdvisorBillLine(name: 'Electricity', amount: 2501),
        ],
        topCategories: [
          AdvisorCategoryLine(name: 'Groceries', target: 6000, actual: 5800),
          AdvisorCategoryLine(name: 'Dining', actual: 3200),
        ],
      );

      final s = ctx.financeSnapshotSummary();

      expect(s, contains('Total liquid cash: ₱42,351'));
      expect(s, contains('Forecasted ending cash'));
      expect(s, contains('₱1,234,567'));
      expect(s, contains('Net cash flow this month: -₱5,400'));
      expect(s, contains('Savings rate this month: 18%'));
      expect(s, contains('₱15,250 spent of ₱20,000 target (₱4,750 remaining)'));
      expect(s, contains('unused capacity'));
      expect(s, contains('Days left in month: 9'));
      // Bills itemised + totalled.
      expect(s, contains('Internet: ₱1,699'));
      expect(s, contains('Total outstanding: ₱4,200'));
      // Category with a budget shows actual vs target; one without says so.
      expect(s, contains('Groceries: ₱5,800 of ₱6,000 target'));
      expect(s, contains('Dining: ₱3,200 spent (no budget set)'));
    });

    test('empty snapshot yields a clear placeholder', () {
      const ctx = AiCoachContext(entryPoint: AiCoachEntryPoint.financeAdvisor);
      expect(ctx.financeSnapshotSummary(), '(no financial data available)');
    });
  });

  group('AiCoachPresenter.looksLikeExpenseLog', () {
    test('treats questions as advice, never logs', () {
      expect(
          AiCoachPresenter.looksLikeExpenseLog('can I afford a ₱4000 dinner?'),
          isFalse);
      expect(AiCoachPresenter.looksLikeExpenseLog('how is my positioning?'),
          isFalse);
    });

    test('detects clear logging phrases', () {
      expect(
          AiCoachPresenter.looksLikeExpenseLog('spent 500 on lunch'), isTrue);
      expect(AiCoachPresenter.looksLikeExpenseLog('paid ₱1,699 for internet'),
          isTrue);
      expect(AiCoachPresenter.looksLikeExpenseLog('coffee 120'), isTrue);
    });

    test('advisory prose without an amount is not a log', () {
      expect(AiCoachPresenter.looksLikeExpenseLog('should I start investing'),
          isFalse);
    });
  });
}
