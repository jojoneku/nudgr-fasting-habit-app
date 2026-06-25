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

    test('roundtrip preserves reimbursable flag and receivable link', () {
      final txn = TransactionRecord(
        id: 't2',
        date: DateTime(2026, 4, 1),
        accountId: 'a0',
        categoryId: 'c1',
        amount: 1200,
        type: TransactionType.outflow,
        description: 'Client dinner',
        month: '2026-04',
        reimbursable: true,
        reimbursementReceivableId: 'r9',
        owedBy: 'Acme Corp',
      );
      final txn2 = TransactionRecord.fromJson(txn.toJson());
      expect(txn2.reimbursable, isTrue);
      expect(txn2.reimbursementReceivableId, 'r9');
      expect(txn2.owedBy, 'Acme Corp');
    });

    test('legacy JSON (no reimbursable keys) loads with safe defaults', () {
      // A row written before the reimbursable fields existed must deserialize
      // unchanged: not reimbursable, no link.
      final json = {
        'id': 't_old',
        'date': DateTime(2026, 1, 1).toIso8601String(),
        'accountId': 'a0',
        'categoryId': 'c1',
        'amount': 300.0,
        'type': 'outflow',
        'description': 'Lunch',
        'month': '2026-01',
      };
      final txn = TransactionRecord.fromJson(json);
      expect(txn.reimbursable, isFalse);
      expect(txn.reimbursementReceivableId, isNull);
      expect(txn.owedBy, isNull);
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

    test('null-tolerant: a corrupt row (null amount) loads with defaults', () {
      // Mirrors a real bad cloud row (finance_bills/bill_spotify_*) that used
      // to throw 'Null is not a subtype of num' out of pullAll and be dropped.
      final json = {
        'id': 'bill_spotify_2026_06',
        'name': 'Spotify',
        'billType': 'subscription',
        'amount': null,
        'dueDay': null,
        'month': '2026-06',
        'categoryId': null,
      };
      final bill = Bill.fromJson(json);
      expect(bill.amount, 0);
      expect(bill.dueDay, 1);
      expect(bill.categoryId, '');
      expect(bill.billType, BillType.subscription);
    });
  });

  group('BudgetedExpense', () {
    test('roundtrip preserves note and spentAmount', () {
      final exp = BudgetedExpense(
        id: 'e1',
        name: 'Family Allowance',
        budgetedType: SetAsideType.sinkingFund,
        month: '2026-04',
        allocatedAmount: 10000,
        spentAmount: 9500,
        categoryId: 'c3',
        note: 'Maya Savings',
      );
      final exp2 = BudgetedExpense.fromJson(exp.toJson());
      expect(exp2.note, 'Maya Savings');
      expect(exp2.spentAmount, 9500);
      expect(exp2.budgetedType, SetAsideType.sinkingFund);
    });

    test('legacy BillType-valued budgetedType migrates to SetAsideType.other',
        () {
      // Pre-existing rows stored a BillType name (e.g. "utility"). These must
      // load without throwing and fall back to `other`.
      final json = {
        'id': 'e9',
        'name': 'Old row',
        'budgetedType': 'utility', // legacy BillType value
        'month': '2026-01',
        'allocatedAmount': 500.0,
        'categoryId': '',
      };
      expect(BudgetedExpense.fromJson(json).budgetedType, SetAsideType.other);
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

    test('roundtrip preserves reimbursement back-link', () {
      final rec = Receivable(
        id: 'r9',
        name: 'Client dinner',
        receivableType: ReceivableType.reimbursement,
        amount: 1200,
        expectedDate: DateTime(2026, 5, 1),
        month: '2026-04',
        categoryId: 'c4',
        reimbursementForTxnId: 't2',
      );
      final rec2 = Receivable.fromJson(rec.toJson());
      expect(rec2.receivableType, ReceivableType.reimbursement);
      expect(rec2.reimbursementForTxnId, 't2');
    });

    test('legacy JSON (no reimbursementForTxnId) loads with null link', () {
      final json = {
        'id': 'rcv_old',
        'name': 'Salary',
        'receivableType': 'salary',
        'amount': 51000.0,
        'expectedDate': DateTime(2026, 4, 15).toIso8601String(),
        'month': '2026-04',
        'categoryId': 'c4',
      };
      expect(Receivable.fromJson(json).reimbursementForTxnId, isNull);
    });

    test(
        'null-tolerant: a corrupt row (null String fields) loads with defaults',
        () {
      // Mirrors real bad cloud rows (finance_receivables/rcv_business_expense,
      // rcv_alphaus_july) that used to throw 'Null is not a subtype of String'
      // out of pullAll and be silently dropped.
      final json = {
        'id': 'rcv_business_expense',
        'name': null,
        'receivableType': null,
        'amount': null,
        'expectedDate': null,
        'month': null,
        'categoryId': null,
      };
      final rec = Receivable.fromJson(json);
      expect(rec.name, '');
      expect(rec.receivableType, ReceivableType.other);
      expect(rec.amount, 0);
      expect(rec.month, '');
      expect(rec.categoryId, '');
      expect(rec.expectedDate, DateTime.fromMillisecondsSinceEpoch(0));
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
