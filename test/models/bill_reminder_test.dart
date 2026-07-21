import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';

Bill _bill({int? reminderDaysBefore}) => Bill(
      id: '1',
      name: 'Internet',
      billType: BillType.utility,
      amount: 100,
      dueDay: 10,
      month: '2026-03',
      categoryId: '',
      reminderDaysBefore: reminderDaysBefore,
    );

void main() {
  test('reminderDaysBefore round-trips through json', () {
    final json = _bill(reminderDaysBefore: 2).toJson();
    expect(json['reminderDaysBefore'], 2);
    expect(Bill.fromJson(json).reminderDaysBefore, 2);
  });

  test('a bill saved before the field loads with no reminder', () {
    final b = Bill.fromJson({
      'id': '1',
      'name': 'Internet',
      'billType': 'utility',
      'amount': 100,
      'dueDay': 10,
      'month': '2026-03',
      'categoryId': '',
    });
    expect(b.reminderDaysBefore, isNull);
  });

  test('copyWith keeps, sets, and clears the reminder', () {
    final b = _bill(reminderDaysBefore: 3);
    expect(b.copyWith().reminderDaysBefore, 3); // omitted → unchanged
    expect(b.copyWith(reminderDaysBefore: 5).reminderDaysBefore, 5);
    expect(b.copyWith(reminderDaysBefore: null).reminderDaysBefore, isNull);
  });
}
