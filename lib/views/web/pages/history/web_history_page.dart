import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import '../../widgets/web_widgets.dart';

/// Web History page (Plan 050-E). STUB — replaced by the History agent.
class WebHistoryPage extends StatelessWidget {
  final TreasuryHistoryPresenter presenter;
  const WebHistoryPage({super.key, required this.presenter});

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
              title: 'History',
              subtitle: 'Month-by-month summaries and trends.',
            ),
            const WebCard(
              child: Text('History redesign in progress — Plan 050-E.'),
            ),
          ],
        ),
      ),
    );
  }
}
