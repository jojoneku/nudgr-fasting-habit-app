import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';

void main() {
  group('FinancialAccount', () {
    test('roundtrip preserves sub-account fields', () {
      final acc = FinancialAccount(
        id: 'a1',
        name: 'Maya Savings',
        category: AccountCategory.savings,
        parentAccountId: 'a0',
        balance: 12500,
        colorHex: '#7C3AED',
        icon: 'bank',
        goalTarget: 50000,
      );
      final acc2 = FinancialAccount.fromJson(acc.toJson());
      expect(acc2.parentAccountId, 'a0');
      expect(acc2.goalTarget, 50000);
      expect(acc2.isSubAccount, isTrue);
      expect(acc2.isLocked, isTrue);
    });

    test('liability account flags correctly', () {
      final cc = FinancialAccount(
        id: 'cc1',
        name: 'Credit Card',
        category: AccountCategory.creditCard,
        balance: 3500,
        colorHex: '#EF4444',
        icon: 'credit-card',
      );
      expect(cc.isLiability, isTrue);
      expect(cc.isLiquid, isFalse);
    });

    test('liquid account flags correctly', () {
      final bank = FinancialAccount(
        id: 'b1',
        name: 'BPI',
        category: AccountCategory.bank,
        balance: 20000,
        colorHex: '#2563EB',
        icon: 'bank',
      );
      expect(bank.isLiquid, isTrue);
      expect(bank.isSubAccount, isFalse);
    });
  });

  group('TransactionRecord', () {
    test('roundtrip preserves transfer fields', () {
      final txn = TransactionRecord(
        id: 't1',
        date: DateTime(2026, 4, 1),
        accountId: 'a0',
        categoryId: 'c1',
        amount: 500,
        type: TransactionType.transfer,
        description: 'Transfer out',
        month: '2026-04',
        transferToAccountId: 'a1',
        transferGroupId: 'tg1',
      );
      final txn2 = TransactionRecord.fromJson(txn.toJson());
      expect(txn2.transferGroupId, 'tg1');
      expect(txn2.transferToAccountId, 'a1');
      expect(txn2.type, TransactionType.transfer);
    });
  });

  group('FinanceCategory', () {
    test('roundtrip preserves all fields', () {
      final cat = FinanceCategory(
        id: 'c1',
        name: 'Food & Drinks',
        type: CategoryType.expense,
        icon: 'food',
        colorHex: '#F59E0B',
      );
      final cat2 = FinanceCategory.fromJson(cat.toJson());
      expect(cat2.type, CategoryType.expense);
      expect(cat2.name, 'Food & Drinks');
    });
  });

  group('Budget', () {
    test('roundtrip preserves group and type', () {
      final budget = Budget(
        id: 'bg1',
        categoryId: 'c1',
        month: '2026-04',
        allocatedAmount: 2500,
        group: BudgetGroup.livingExpense,
        budgetType: BudgetType.variable,
      );
      final budget2 = Budget.fromJson(budget.toJson());
      expect(budget2.group, BudgetGroup.livingExpense);
      expect(budget2.budgetType, BudgetType.variable);
    });
  });

  group('Bill', () {
    test('roundtrip preserves recurrence', () {
      final bill = Bill(
        id: 'b1',
        name: 'Netflix',
        billType: BillType.subscription,
        amount: 459,
        dueDay: 15,
        month: '2026-04',
        categoryId: 'c2',
        isRecurring: true,
        recurrenceType: RecurrenceType.monthly,
        paymentNote: 'GCash 09171234567',
      );
      final bill2 = Bill.fromJson(bill.toJson());
      expect(bill2.recurrenceType, RecurrenceType.monthly);
      expect(bill2.paymentNote, 'GCash 09171234567');
    });
  });

  group('BudgetedExpense', () {
    test('roundtrip preserves note and spentAmount', () {
      final exp = BudgetedExpense(
        id: 'e1',
        name: 'Family Allowance',
        budgetedType: BillType.other,
        month: '2026-04',
        allocatedAmount: 10000,
        spentAmount: 9500,
        categoryId: 'c3',
        note: 'Maya Savings',
      );
      final exp2 = BudgetedExpense.fromJson(exp.toJson());
      expect(exp2.note, 'Maya Savings');
      expect(exp2.spentAmount, 9500);
    });
  });

  group('Receivable', () {
    test('roundtrip preserves receivable type and recurrence', () {
      final rec = Receivable(
        id: 'r1',
        name: 'Salary',
        receivableType: ReceivableType.salary,
        amount: 51000,
        expectedDate: DateTime(2026, 4, 15),
        month: '2026-04',
        categoryId: 'c4',
        isRecurring: true,
        recurrenceType: RecurrenceType.monthly,
      );
      final rec2 = Receivable.fromJson(rec.toJson());
      expect(rec2.receivableType, ReceivableType.salary);
      expect(rec2.recurrenceType, RecurrenceType.monthly);
    });
  });

  group('MonthlySummary', () {
    test('roundtrip preserves maps', () {
      final summary = MonthlySummary(
        month: '2026-03',
        totalInflow: 51000,
        totalOutflow: 42500,
        totalBills: 8000,
        totalBillsPaid: 7500,
        billCount: 10,
        billsPaidCount: 8,
        totalReceivables: 51000,
        totalReceived: 51000,
        receivableCount: 1,
        netSavings: 8500,
        endingCash: 52000,
        accountSnapshots: {'a0': 52000.0},
        categorySpend: {'c2': 459.0},
      );
      final summary2 = MonthlySummary.fromJson(summary.toJson());
      expect(summary2.accountSnapshots['a0'], 52000.0);
      expect(summary2.categorySpend['c2'], 459.0);
      expect(summary2.netSavings, 8500);
    });
  });
}
