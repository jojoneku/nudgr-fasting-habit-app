import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/treasury/shared/quick_pay_sheet.dart';

import '../../../mocks.mocks.dart';

/// Plan 071 Phase 0.2: a failed save must not look like a success. The sheet
/// shows an error toast and stays open, so the entry is not lost.
void main() {
  final cash = FinancialAccount(
    id: 'cash',
    name: 'Wallet',
    category: AccountCategory.cash,
    balance: 5000,
    colorHex: '#16A34A',
    icon: 'cash',
  );
  final card = FinancialAccount(
    id: 'cc',
    name: 'Rewards Card',
    category: AccountCategory.creditCard,
    balance: 1200,
    colorHex: '#DC2626',
    icon: 'creditCard',
  );

  testWidgets('a failed payment shows an error and keeps the sheet open',
      (tester) async {
    final presenter = MockBillsReceivablesPresenter();
    when(presenter.accounts).thenReturn([cash, card]);
    when(presenter.quickPayCard(
      accountId: anyNamed('accountId'),
      fromAccountId: anyNamed('fromAccountId'),
      amount: anyNamed('amount'),
      date: anyNamed('date'),
      note: anyNamed('note'),
    )).thenThrow(StateError('disk full'));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () =>
                showQuickPaySheet(ctx, card: card, presenter: presenter),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final confirm = find.text('Confirm Payment');
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(find.byType(QuickPaySheet), findsOneWidget);
  });
}
