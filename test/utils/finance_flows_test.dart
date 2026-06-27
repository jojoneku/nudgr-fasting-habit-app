import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/finance_flows.dart';

TransactionRecord _txn({
  required String id,
  required TransactionType type,
  double amount = 100,
  bool reimbursable = false,
  String? reimbursementReceivableId,
  String? receivableId,
  String? transferGroupId,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime(2026, 3, 1),
      accountId: 'a1',
      categoryId: 'c1',
      amount: amount,
      type: type,
      description: 'x',
      month: '2026-03',
      reimbursable: reimbursable,
      reimbursementReceivableId: reimbursementReceivableId,
      receivableId: receivableId,
      transferGroupId: transferGroupId,
    );

void main() {
  group('isSpendingOutflow', () {
    test('plain outflow is spending', () {
      expect(isSpendingOutflow(_txn(id: 'o', type: TransactionType.outflow)),
          isTrue);
    });

    test('reimbursable/loan outflow is not spending', () {
      expect(
        isSpendingOutflow(
            _txn(id: 'o', type: TransactionType.outflow, reimbursable: true)),
        isFalse,
      );
    });

    test('transfer leg is not spending', () {
      expect(
        isSpendingOutflow(
            _txn(id: 'o', type: TransactionType.outflow, transferGroupId: 'g')),
        isFalse,
      );
    });

    test('inflow is never spending', () {
      expect(isSpendingOutflow(_txn(id: 'i', type: TransactionType.inflow)),
          isFalse);
    });
  });

  group('income & reimbursement repayments', () {
    test('reimbursementReceivableIds collects spawned receivable ids', () {
      final ids = reimbursementReceivableIds([
        _txn(
            id: 'lent',
            type: TransactionType.outflow,
            reimbursable: true,
            reimbursementReceivableId: 'r1'),
        _txn(id: 'normal', type: TransactionType.outflow),
        _txn(id: 'salary', type: TransactionType.inflow),
      ]);
      expect(ids, {'r1'});
    });

    test('plain inflow is income; reimbursement repayment is not', () {
      final reimb = {'r1'};
      // Salary — real income.
      expect(
        isIncomeInflow(_txn(id: 'salary', type: TransactionType.inflow), reimb),
        isTrue,
      );
      // Repayment of a loan/reimbursable — your own money back, not income.
      expect(
        isIncomeInflow(
            _txn(id: 'pay', type: TransactionType.inflow, receivableId: 'r1'),
            reimb),
        isFalse,
      );
      // A salary receivable settlement (id not from a reimbursable) IS income.
      expect(
        isIncomeInflow(
            _txn(id: 'sal2', type: TransactionType.inflow, receivableId: 'r9'),
            reimb),
        isTrue,
      );
    });

    test('transfer inflow leg is not income', () {
      expect(
        isIncomeInflow(
            _txn(id: 'i', type: TransactionType.inflow, transferGroupId: 'g'),
            const {}),
        isFalse,
      );
    });
  });
}
