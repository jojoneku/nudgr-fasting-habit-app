import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import '../../widgets/web_widgets.dart';

/// Web Dashboard page (Plan 050-A). STUB — replaced by the Dashboard agent.
class WebDashboardPage extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const WebDashboardPage({super.key, required this.presenter});

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
              title: 'Dashboard',
              subtitle: 'Your financial position at a glance.',
            ),
            const WebCard(
              child: Text('Dashboard redesign in progress — Plan 050-A.'),
            ),
          ],
        ),
      ),
    );
  }
}
