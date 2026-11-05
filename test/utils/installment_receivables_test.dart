import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/utils/installment_receivables.dart';

/// The receivables of a plan bought for someone else (Plan 067): one per
/// payment month; open ones follow the plan, received ones never change.
void main() {
  Installment plan({
    String? paidFor = 'Papa',
    int months = 3,
    double monthly = 1000,
    String start = '2026-11',
    bool isActive = true,
  }) =>
      Installment(
        id: 'x',
        name: 'Xiaomi Redmi Note 15',
        accountId: 'card',
        totalAmount: monthly * months,
        monthlyAmount: monthly,
        totalMonths: months,
        startMonth: start,
        isActive: isActive,
        paidForName: paidFor,
      );

  List<InstallmentReceivableStep> steps(
    Installment? p,
    List<Receivable> linked, {
    int billedCount = 0,
  }) =>
      planInstallmentReceivables(
        planId: 'x',
        plan: p,
        linked: linked,
        categoryId: 'cat-tech',
        dueDateFor: (m) => DateTime.parse('$m-04'),
        billedCount: billedCount,
      );

  /// The receivables the steps leave behind, as they would be saved.
  List<Receivable> apply(
      List<Receivable> linked, List<InstallmentReceivableStep> s) {
    final byId = {for (final r in linked) r.id: r};
    for (final step in s) {
      if (!step.writes) continue;
      if (step.change == InstallmentReceivableChange.remove) {
        byId.remove(step.receivable.id);
      } else {
        byId[step.receivable.id] = step.receivable;
      }
    }
    return byId.values.toList();
  }

  List<InstallmentReceivableChange> changes(
          List<InstallmentReceivableStep> s) =>
      [for (final step in s) step.change];

  test('a new plan for someone gets one receivable per payment month', () {
    final s = steps(plan(), const []);
    expect(changes(s), everyElement(InstallmentReceivableChange.add));
    final made = [for (final step in s) step.receivable];
    expect([for (final r in made) r.month], ['2026-11', '2026-12', '2027-01']);
    expect([for (final r in made) r.id],
        ['instrcv_x_1', 'instrcv_x_2', 'instrcv_x_3']);
    final first = made.first;
    expect(first.name, 'Papa — Xiaomi Redmi Note 15 (1/3)');
    expect(first.amount, 1000);
    expect(first.receivableType, ReceivableType.reimbursement);
    expect(first.expectedDate, DateTime(2026, 11, 4));
    expect(first.categoryId, 'cat-tech');
    expect(first.installmentId, 'x');
    expect(first.installmentNumber, 1);
    expect(first.isReceived, isFalse);
  });

  test('a plan for yourself with no receivables does nothing', () {
    expect(steps(plan(paidFor: null), const []), isEmpty);
  });

  test('running again over its own result changes nothing', () {
    final made = apply(const [], steps(plan(), const []));
    final again = steps(plan(), made);
    expect(changes(again), everyElement(InstallmentReceivableChange.unchanged));
    expect(again.any((s) => s.writes), isFalse);
  });

  group('edit', () {
    late List<Receivable> made;
    setUp(() => made = apply(const [], steps(plan(), const [])));

    Receivable received(Receivable r) => r.copyWith(
          isReceived: true,
          receivedAmount: r.amount,
          receivedDate: DateTime(2026, 11, 5),
        );

    test('a new amount moves to the open ones, not to the received one', () {
      final linked = [received(made[0]), made[1], made[2]];
      final s = steps(plan(monthly: 1200), linked);
      expect(changes(s), [
        InstallmentReceivableChange.keepReceived,
        InstallmentReceivableChange.update,
        InstallmentReceivableChange.update,
      ]);
      final after = apply(linked, s);
      expect(after.firstWhere((r) => r.installmentNumber == 1).amount, 1000);
      expect(after.firstWhere((r) => r.installmentNumber == 2).amount, 1200);
      expect(after.firstWhere((r) => r.installmentNumber == 3).amount, 1200);
    });

    test('a later start month moves the open ones to the new months', () {
      final linked = [received(made[0]), made[1], made[2]];
      final after = apply(linked, steps(plan(start: '2027-02'), linked));
      expect(after.firstWhere((r) => r.installmentNumber == 1).month, '2026-11',
          reason: 'received: stays where it was paid');
      expect(
          after.firstWhere((r) => r.installmentNumber == 2).month, '2027-03');
      expect(after.firstWhere((r) => r.installmentNumber == 2).expectedDate,
          DateTime(2027, 3, 4));
      expect(
          after.firstWhere((r) => r.installmentNumber == 3).month, '2027-04');
    });

    test('fewer months removes the extra open ones', () {
      final s = steps(plan(months: 2), made);
      expect(changes(s), [
        InstallmentReceivableChange.update, // name now says (1/2)
        InstallmentReceivableChange.update,
        InstallmentReceivableChange.remove,
      ]);
      final after = apply(made, s);
      expect(after.map((r) => r.installmentNumber), [1, 2]);
      expect(after.first.name, 'Papa — Xiaomi Redmi Note 15 (1/2)');
    });

    test('fewer months never removes a received one', () {
      final linked = [made[0], made[1], received(made[2])];
      final after = apply(linked, steps(plan(months: 2), linked));
      expect(after.map((r) => r.installmentNumber), containsAll([1, 2, 3]));
      expect(
          after.firstWhere((r) => r.installmentNumber == 3).isReceived, isTrue);
    });

    test('more months adds the missing ones', () {
      final s = steps(plan(months: 5), made);
      expect(s.where((x) => x.change == InstallmentReceivableChange.add).length,
          2);
      expect(apply(made, s).map((r) => r.month),
          containsAll(['2027-02', '2027-03']));
    });

    test('a received payment number is not made again', () {
      final linked = [received(made[0]), made[1], made[2]];
      final s = steps(plan(), linked);
      expect(
          s.where((x) => x.change == InstallmentReceivableChange.add), isEmpty);
    });

    test('a new person renames the open ones', () {
      final after = apply(made, steps(plan(paidFor: 'Mama'), made));
      expect(after.every((r) => r.name.startsWith('Mama — ')), isTrue);
    });

    test('toggle off deletes open ones and unlinks received ones', () {
      final linked = [received(made[0]), made[1], made[2]];
      final s = steps(plan(paidFor: null), linked);
      expect(changes(s), [
        InstallmentReceivableChange.unlinkReceived,
        InstallmentReceivableChange.remove,
        InstallmentReceivableChange.remove,
      ]);
      final after = apply(linked, s);
      expect(after, hasLength(1));
      expect(after.single.isReceived, isTrue);
      expect(after.single.installmentId, isNull);
      expect(after.single.installmentNumber, isNull);
      expect(s.first.number, 1, reason: 'the step keeps the old number');
    });

    test('a deleted plan acts like toggle off', () {
      final linked = [received(made[0]), made[1], made[2]];
      final after = apply(linked, steps(null, linked));
      expect(after, hasLength(1));
      expect(after.single.installmentId, isNull);
    });

    test('a cancelled plan keeps the months it already billed', () {
      final s = steps(plan(isActive: false), made, billedCount: 1);
      final after = apply(made, s);
      expect(after.map((r) => r.installmentNumber), [1]);
    });
  });
}
