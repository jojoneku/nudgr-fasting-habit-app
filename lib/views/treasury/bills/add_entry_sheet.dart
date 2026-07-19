import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

enum _EntryMode { bill, receivable }

/// Combined "New entry" sheet (reference `Nutrition Focus Treasury.dc.html`):
/// a Bill-to-pay / Money-owed-me toggle over the two entry forms. Each form
/// keeps its own fields and save logic (hosted in `embedded` mode so only this
/// sheet's title shows); both stay mounted via [IndexedStack] so switching the
/// toggle doesn't discard what was already typed on the other side.
class AddEntrySheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final bool startAsReceivable;

  const AddEntrySheet({
    super.key,
    required this.presenter,
    this.startAsReceivable = false,
  });

  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  late _EntryMode _mode =
      widget.startAsReceivable ? _EntryMode.receivable : _EntryMode.bill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Cap the sheet height so the Flexible below has a bounded constraint (a raw
    // scroll-controlled modal otherwise hands down an unbounded height, which
    // would make Flexible throw). The hosted forms scroll within this cap.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New entry',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                AppSegmentedControl<_EntryMode>(
                  segments: const [
                    (value: _EntryMode.bill, label: 'Bill to pay', icon: null),
                    (
                      value: _EntryMode.receivable,
                      label: 'Money owed me',
                      icon: null
                    ),
                  ],
                  selected: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
              ],
            ),
          ),
          Flexible(
            child: IndexedStack(
              index: _mode == _EntryMode.bill ? 0 : 1,
              sizing: StackFit.loose,
              children: [
                AddBillSheet(presenter: widget.presenter, embedded: true),
                AddReceivableSheet(presenter: widget.presenter, embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
