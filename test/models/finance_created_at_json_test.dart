// `createdAt` on the four finance records Nudgy is asked "when did I add
// this?" about (Plan 065 phase 3). The sync code pushes `toJson()` as the cloud
// row's `data` and pulls it back through `fromJson`, so a JSON round-trip is
// exactly what a sync does to the field.

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';

void main() {
  final created = DateTime(2026, 10, 3, 9, 15, 30);

  Bill bill({DateTime? createdAt}) => Bill(
        id: 'b1',
        name: 'Internet',
        billType: BillType.utility,
        amount: 1500,
        dueDay: 4,
        month: '2026-10',
        categoryId: 'c1',
        createdAt: createdAt,
      );

  Receivable receivable({DateTime? createdAt}) => Receivable(
        id: 'r1',
        name: 'Salary',
        receivableType: ReceivableType.salary,
        amount: 30000,
        month: '2026-10',
        categoryId: 'c1',
        createdAt: createdAt,
      );

  TransactionRecord txn({DateTime? createdAt}) => TransactionRecord(
        id: 't1',
        date: DateTime(2026, 10, 3),
        accountId: 'a1',
        categoryId: 'c1',
        amount: 250,
        type: TransactionType.outflow,
        description: 'Lunch',
        month: '2026-10',
        createdAt: createdAt,
      );

  BudgetedExpense expense({DateTime? createdAt}) => BudgetedExpense(
        id: 'e1',
        name: 'Emergency fund',
        budgetedType: SetAsideType.savings,
        month: '2026-10',
        allocatedAmount: 2000,
        categoryId: 'c1',
        createdAt: createdAt,
      );

  group('Bill.createdAt', () {
    test('survives a JSON round-trip', () {
      final json = bill(createdAt: created).toJson();
      expect(json['createdAt'], created.toIso8601String());
      expect(Bill.fromJson(json).createdAt, created);
    });

    test('a record without the field loads with null', () {
      final json = bill().toJson()..remove('createdAt');
      expect(Bill.fromJson(json).createdAt, isNull);
      expect(Bill.fromJson(bill().toJson()).createdAt, isNull);
    });

    test('an unparseable or mistyped value loads as null', () {
      expect(
          Bill.fromJson(bill().toJson()..['createdAt'] = 'garbage').createdAt,
          isNull);
      expect(
          Bill.fromJson(bill().toJson()..['createdAt'] = 42).createdAt, isNull);
    });

    test('copyWith keeps it; an explicit value replaces it', () {
      final b = bill(createdAt: created);
      expect(b.copyWith(name: 'Fiber').createdAt, created);
      expect(b.copyWith(createdAt: null).createdAt, isNull);
    });
  });

  group('Receivable.createdAt', () {
    test('survives a JSON round-trip', () {
      final json = receivable(createdAt: created).toJson();
      expect(Receivable.fromJson(json).createdAt, created);
    });

    test('a record without the field loads with null', () {
      final json = receivable().toJson()..remove('createdAt');
      expect(Receivable.fromJson(json).createdAt, isNull);
      expect(
          Receivable.fromJson(receivable().toJson()..['createdAt'] = 'x')
              .createdAt,
          isNull);
    });

    test('copyWith keeps it', () {
      expect(receivable(createdAt: created).copyWith(amount: 1).createdAt,
          created);
    });
  });

  group('TransactionRecord.createdAt', () {
    test('survives a JSON round-trip', () {
      final json = txn(createdAt: created).toJson();
      expect(TransactionRecord.fromJson(json).createdAt, created);
    });

    test('a record without the field loads with null', () {
      final json = txn().toJson()..remove('createdAt');
      expect(TransactionRecord.fromJson(json).createdAt, isNull);
      expect(
          TransactionRecord.fromJson(txn().toJson()..['createdAt'] = '')
              .createdAt,
          isNull);
    });

    test('copyWith keeps it; an explicit value replaces it', () {
      final t = txn(createdAt: created);
      expect(t.copyWith(amount: 300).createdAt, created);
      expect(t.copyWith(createdAt: null).createdAt, isNull);
    });
  });

  group('BudgetedExpense.createdAt', () {
    test('survives a JSON round-trip', () {
      final json = expense(createdAt: created).toJson();
      expect(BudgetedExpense.fromJson(json).createdAt, created);
    });

    test('a record without the field loads with null', () {
      final json = expense().toJson()..remove('createdAt');
      expect(BudgetedExpense.fromJson(json).createdAt, isNull);
      expect(
          BudgetedExpense.fromJson(expense().toJson()..['createdAt'] = 'x')
              .createdAt,
          isNull);
    });

    test('copyWith keeps it', () {
      expect(expense(createdAt: created).copyWith(isPaid: true).createdAt,
          created);
    });
  });
}
