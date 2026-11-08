import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// What the archive confirm says before
/// `TreasuryDashboardPresenter.archiveGoal` runs. Archiving sets `isActive`
/// to false: the account leaves the goal lists and every account picker, a
/// top-level account's balance stops counting toward the totals, and nothing
/// is deleted. Shared by
/// the mobile account form, the mobile Goals screen, the web Setup row menu
/// and the web Goals card menu, so all four say the same thing.
///
/// Neither app has a way to bring an archived account back yet, so the copy
/// promises none. On web the account is still listed under "Archived" in the
/// Dashboard's "All accounts" dialog, which [onWeb] adds; mobile has no such
/// list.
String accountArchiveTitle(FinancialAccount account) =>
    'Archive ${account.name}?';

String accountArchiveMessage(FinancialAccount account, {bool onWeb = false}) {
  final buffer = StringBuffer(
      'Takes "${account.name}" out of your goal lists and account pickers. '
      'Nothing is deleted: its transactions stay in your ledger.');
  // A pocket's money is counted inside its parent, which archiving leaves
  // alone; only a top-level account's balance drops out of the totals.
  if (account.balance > 0 &&
      account.parentAccountId == null &&
      !account.isCustodian) {
    buffer.write(' The ${formatPeso(account.balance)} still in it stops '
        'counting toward your totals and net worth.');
  }
  if (onWeb) {
    buffer.write(' It stays listed under Archived in "All accounts" on the '
        'Dashboard.');
  }
  return buffer.toString();
}

/// The toast after a successful archive.
String accountArchivedToast(FinancialAccount account) =>
    'Archived ${account.name}';
