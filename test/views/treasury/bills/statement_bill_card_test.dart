import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/statement_card_view.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/bills/statement_bill_card.dart';

StatementCardView _view({bool paid = false, double? progress}) =>
    StatementCardView(
      bill: Bill(
        id: 's1',
        name: 'ShopeePay statement',
        billType: BillType.creditCard,
        amount: 2424.40,
        dueDay: 15,
        month: '2026-10',
        categoryId: '',
        accountId: 'spay',
        isPaid: paid,
      ),
      account: FinancialAccount(
        id: 'spay',
        name: 'ShopeePay',
        category: AccountCategory.bnpl,
        balance: 2424.40,
        colorHex: '#D97706',
        icon: 'bag',
      ),
      periodLabel: 'Statement · 05 Sep – 04 Oct',
      unpaid: paid ? 0 : (progress == null ? 2424.40 : 1574.40),
      amount: 2424.40,
      dueLabel: paid ? 'Paid Oct 10' : 'Due Oct 15 · in 8 days',
      dueTone: paid ? StatementDueTone.paid : StatementDueTone.normal,
      progress: progress,
      progressLabel: progress == null ? null : 'Paid ₱850.00 of ₱2,424.40',
      minimumLabel: paid ? null : 'Min ₱850.00',
      compositionLabel: '3 purchases · 6 installments',
      itemsLabel: 'View 9 items',
    );

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    );

void main() {
  testWidgets('shows the account, cycle, what is left and what is on it',
      (tester) async {
    await _pump(tester, StatementBillCard(view: _view(), onPay: () {}));

    expect(find.text('ShopeePay'), findsOneWidget);
    expect(find.text('BNPL'), findsOneWidget);
    expect(find.text('Statement · 05 Sep – 04 Oct'), findsOneWidget);
    expect(find.text('₱2,424.40'), findsOneWidget);
    expect(find.text('To pay · Min ₱850.00'), findsOneWidget);
    expect(find.text('Due Oct 15 · in 8 days'), findsOneWidget);
    expect(find.text('3 purchases · 6 installments'), findsOneWidget);
    expect(find.text('View 9 items'), findsOneWidget);
    expect(find.text('Pay'), findsOneWidget);
  });

  testWidgets('the items strip and Pay fire their own callbacks',
      (tester) async {
    var items = 0;
    var pay = 0;
    var edit = 0;
    await _pump(
      tester,
      StatementBillCard(
        view: _view(),
        onPay: () => pay++,
        onViewItems: () => items++,
        onEdit: () => edit++,
      ),
    );

    await tester.tap(find.text('View 9 items'));
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();

    expect(items, 1);
    expect(pay, 1);
    expect(edit, 0);
  });

  testWidgets('a part-paid statement shows its progress', (tester) async {
    await _pump(tester, StatementBillCard(view: _view(progress: 0.35)));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Paid ₱850.00 of ₱2,424.40'), findsOneWidget);
  });

  testWidgets('a paid statement offers Undo instead of Pay', (tester) async {
    await _pump(
      tester,
      StatementBillCard(view: _view(paid: true), onPay: () {}, onUndo: () {}),
    );

    expect(find.text('Pay'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Paid Oct 10'), findsOneWidget);
  });
}
