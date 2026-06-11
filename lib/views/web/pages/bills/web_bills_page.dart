import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import '../../widgets/web_widgets.dart';

/// Web Bills & Receivables page (Plan 050-C). STUB — replaced by the Bills agent.
class WebBillsPage extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  const WebBillsPage({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WebSectionHeader(
              title: 'Bills & Receivables',
              subtitle: 'What you owe and what is owed to you.',
            ),
            const WebCard(
              child: Text('Bills redesign in progress — Plan 050-C.'),
            ),
          ],
        ),
      ),
    );
  }
}
