import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import '../../widgets/web_widgets.dart';

/// Web Budget page (Plan 050-D). STUB — replaced by the Budget agent.
class WebBudgetPage extends StatelessWidget {
  final BudgetPresenter presenter;
  const WebBudgetPage({super.key, required this.presenter});

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
              title: 'Budget',
              subtitle: 'Allocations vs. actual spend this month.',
            ),
            const WebCard(
              child: Text('Budget redesign in progress — Plan 050-D.'),
            ),
          ],
        ),
      ),
    );
  }
}
