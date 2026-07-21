import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/due_soon_hero.dart';
import 'package:intl/intl.dart';

/// A horizontally swipeable stack of the due-soon / overdue unpaid bills, each
/// rendered as a [DueSoonHero] card. Renders nothing when nothing is imminent.
///
/// Dumb-ish: it reads the imminent list and per-bill due label/subtitle from the
/// presenter's getters (no date math in `build`, Rule 1) and forwards actions to
/// the existing mark-paid / edit sheets via callbacks.
class DueSoonStack extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final void Function(Bill) onMarkPaid;
  final void Function(Bill) onEdit;

  const DueSoonStack({
    super.key,
    required this.presenter,
    required this.onMarkPaid,
    required this.onEdit,
  });

  @override
  State<DueSoonStack> createState() => _DueSoonStackState();
}

class _DueSoonStackState extends State<DueSoonStack> {
  // Full-width pages so the hero card fills the available content width (the
  // list already insets 16px each side). The stacked-deck plates + page dots
  // signal there's more to swipe, so we don't need a peek of the next card.
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _subtitle(Bill bill) {
    final categoryName = widget.presenter.categories
        .where((c) => c.id == bill.categoryId)
        .firstOrNull
        ?.name;
    return [
      if (categoryName != null && categoryName.isNotEmpty) categoryName,
      'due ${DateFormat('MMM d').format(widget.presenter.billDueDate(bill))}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final bills = widget.presenter.imminentUnpaidBills;
    if (bills.isEmpty) return const SizedBox.shrink();

    // Clamp the tracked page if the list shrank (e.g. a bill was just paid).
    final page = _page.clamp(0, bills.length - 1);

    return Column(
      children: [
        SizedBox(
          height: 176,
          child: _StackedDeck(
            showDeck: bills.length > 1,
            child: PageView.builder(
              controller: _controller,
              itemCount: bills.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final bill = bills[i];
                final due = widget.presenter.billDueInfo(bill);
                return Padding(
                  // A hairline gap so adjacent cards don't touch mid-swipe,
                  // without meaningfully narrowing the card.
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: DueSoonHero(
                    billName: bill.name,
                    amount: bill.amount,
                    dueLabel: due.label,
                    subtitle: _subtitle(bill),
                    overdue: due.overdue,
                    onMarkPaid: () => widget.onMarkPaid(bill),
                    onEdit: () => widget.onEdit(bill),
                  ),
                );
              },
            ),
          ),
        ),
        if (bills.length > 1) ...[
          const SizedBox(height: 10),
          _PageDots(count: bills.length, active: page),
        ],
      ],
    );
  }
}

/// Two faint rounded plates peeking beneath the active card to imply a swipeable
/// deck. Purely decorative; hidden for a single card.
class _StackedDeck extends StatelessWidget {
  final bool showDeck;
  final Widget child;

  const _StackedDeck({required this.showDeck, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!showDeck) return child;
    final cs = Theme.of(context).colorScheme;

    Widget plate(double inset, double drop, double alpha) => Positioned(
          left: inset,
          right: inset,
          bottom: -drop,
          child: Container(
            height: 26,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4 * alpha),
              ),
            ),
          ),
        );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        plate(28, 10, 0.5),
        plate(18, 5, 0.8),
        child,
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int active;

  const _PageDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = context.appColors.bills;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active
                  ? accent
                  : cs.onSurfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
