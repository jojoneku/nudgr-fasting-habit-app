import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/statement_card.dart';

/// The Next Month Forecast — the Month-End Outlook carried one month on,
/// placed directly under [MonthEndOutlookCard] so the two read as a pair.
///
/// It starts where this month's outlook ends (Projected month-end) and runs
/// the same chain, line for line:
///
///   Starts at + To receive − Bills − Installments − Set-asides − Budget
///     = Projected end of next month
///
/// Every figure is [TreasuryDashboardPresenter.nextMonthForecast]; this widget
/// only lays it out, in the same [StatementCard] as the outlook.
class NextMonthForecastCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const NextMonthForecastCard({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final f = presenter.nextMonthForecast;
    return StatementCard(
      title: 'Next month forecast',
      hint: f.monthName,
      lines: f.lines,
      endingTitle: f.endingTitle,
      endingCaption: f.changeLabel,
      endingAmount: f.endingLabel,
      endingTone: f.endingTone,
    );
  }
}
