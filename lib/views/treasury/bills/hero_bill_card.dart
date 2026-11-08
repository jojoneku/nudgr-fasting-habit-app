import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/due_soon_hero.dart';
import 'package:intl/intl.dart';

/// Keys for the Bills hero, for tests.
abstract final class HeroBillCardKeys {
  static const card = ValueKey('bills-hero-card');
}

/// "{Category} · due {Mmm d}" — the line under a due-soon hero's bill name.
/// Top-level so the desktop Bills page composes the identical subtitle instead
/// of re-deriving one that drifts from the phone's.
String dueSoonSubtitle(BillsReceivablesPresenter presenter, Bill bill) {
  final categoryName = presenter.categories
      .where((c) => c.id == bill.categoryId)
      .firstOrNull
      ?.name;
  return [
    if (categoryName != null && categoryName.isNotEmpty) categoryName,
    'due ${DateFormat('MMM d').format(presenter.billDueDate(bill))}',
  ].join(' · ');
}

/// The Bills tab hero: one [DueSoonHero] for the presenter's
/// [BillsReceivablesPresenter.heroBill], the most imminent unpaid bill.
/// Renders nothing when no bill is overdue or due within a week.
///
/// It shows one bill only (Plan 071 Phase 6). The other due-soon bills are
/// listed at the top of the Upcoming tab, so no bill appears twice.
///
/// [onMarkPaid] and [onEdit] are null while a batch selection is running, so
/// the hero cannot act outside the batch.
class HeroBillCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final void Function(Bill)? onMarkPaid;
  final void Function(Bill)? onEdit;

  const HeroBillCard({
    super.key,
    required this.presenter,
    required this.onMarkPaid,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final bill = presenter.heroBill;
    if (bill == null) return const SizedBox.shrink();
    final due = presenter.billDueInfo(bill);
    final markPaid = onMarkPaid;
    final edit = onEdit;
    return Padding(
      key: HeroBillCardKeys.card,
      padding: const EdgeInsets.only(bottom: 16),
      child: DueSoonHero(
        billName: bill.name,
        amount: bill.amount,
        dueLabel: due.label,
        subtitle: dueSoonSubtitle(presenter, bill),
        overdue: due.overdue,
        onMarkPaid: markPaid == null ? null : () => markPaid(bill),
        onEdit: edit == null ? null : () => edit(bill),
      ),
    );
  }
}
