import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';
import '../../widgets/web_widgets.dart';

/// Presents one of the existing mobile add/edit sheets inside the shared
/// [WebDialog] so the web page can reuse them verbatim (Plan 050-C, house rule
/// #4). The sheets build with `MainAxisSize.min`, so the scrollable dialog hugs
/// their content height.
Future<void> showBillsDialog(BuildContext context, Widget sheet) {
  return showWebDialog<void>(context: context, maxWidth: 520, child: sheet);
}

/// Opens the Add/Edit Bill sheet as a web dialog. Pass [existing] to edit.
Future<void> showAddBillDialog(
  BuildContext context,
  BillsReceivablesPresenter presenter, {
  Bill? existing,
}) {
  return showBillsDialog(
    context,
    AddBillSheet(presenter: presenter, existing: existing),
  );
}

/// Opens the Add/Edit Receivable sheet as a web dialog. Pass [existing] to edit.
Future<void> showAddReceivableDialog(
  BuildContext context,
  BillsReceivablesPresenter presenter, {
  Receivable? existing,
}) {
  return showBillsDialog(
    context,
    AddReceivableSheet(presenter: presenter, existing: existing),
  );
}

/// Opens the Add/Edit Installment sheet as a web dialog. Pass [existing] to edit.
Future<void> showAddInstallmentDialog(
  BuildContext context,
  InstallmentPresenter presenter, {
  Installment? existing,
}) {
  return showBillsDialog(
    context,
    AddInstallmentSheet(presenter: presenter, existing: existing),
  );
}
