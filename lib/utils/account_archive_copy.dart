import 'package:intermittent_fasting/models/finance/financial_account.dart';

/// What the archive confirm says before
/// `TreasuryDashboardPresenter.archiveGoal` runs. Archiving sets `isActive`
/// to false: the account leaves every list and picker, and nothing is
/// deleted. Shared by the mobile account form, the mobile Goals screen, the
/// web Setup row menu and the web Goals card menu, so all four say the same
/// thing.
String accountArchiveTitle(FinancialAccount account) =>
    'Archive ${account.name}?';

String accountArchiveMessage(FinancialAccount account) =>
    'Hides "${account.name}" from every list and picker. Nothing is deleted: '
    'its transactions stay in your ledger.';

/// The toast after a successful archive.
String accountArchivedToast(FinancialAccount account) =>
    'Archived ${account.name}';
