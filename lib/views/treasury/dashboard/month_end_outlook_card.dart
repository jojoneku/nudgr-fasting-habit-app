import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/statement_card.dart';

/// The Month-End Outlook as a signed statement — every figure that makes up
/// the month-end projection, in the same order and under the same labels the
/// web companion uses (`web_dashboard_page_v2.dart` → `_OutlookCard`):
///
///   Liquid now + To receive − Upcoming bills − Set-asides due
///     − Budget left = Projected month-end
///
/// Every deduction is on screen so the drop from liquid cash to the
/// projection reconciles. "Budget left" is
/// [TreasuryDashboardPresenter.budgetRemainingNetOfObligations] rather than
/// raw `totalBudgetRemaining` so the chain closes.
///
/// The projection is [TreasuryDashboardPresenter.forecastedNetBalance], not
/// raw `endingCash` (which does not reserve the remaining budget). It is shown
/// here and as the Next Month Forecast's "Starts at", nowhere else.
///
/// Every line comes from [TreasuryDashboardPresenter.monthEndOutlook]; this
/// widget only lays it out, in the same [StatementCard] as the forecast.
class MonthEndOutlookCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const MonthEndOutlookCard({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final outlook = presenter.monthEndOutlook;
    return StatementCard(
      title: 'Month-end outlook',
      lines: outlook.lines,
      endingTitle: outlook.projectedTitle,
      endingCaption: outlook.projectedCaption,
      endingAmount: outlook.projectedLabel,
      endingTone: outlook.projectedTone,
    );
  }
}
