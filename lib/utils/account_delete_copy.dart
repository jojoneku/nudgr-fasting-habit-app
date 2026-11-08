import 'package:intermittent_fasting/models/finance/financial_account.dart';

/// What the delete confirm says before
/// `TreasuryDashboardPresenter.deleteAccount` runs. The presenter enforces the
/// rule — it refuses with `StateError('has_sub_accounts')` when pockets still
/// sit under the account and `StateError('has_transactions')` when any
/// transaction or bill still references it — so this text only explains that
/// rule; nothing is deleted around it. Shared by mobile and web so neither
/// promises a delete the presenter will refuse.
String accountDeleteMessage(FinancialAccount account) =>
    'This removes "${account.name}" from every list and picker. An account '
    'with transactions or bills linked to it cannot be deleted — delete or '
    'reassign those first (a goal can be archived instead, which keeps its '
    'history). Pockets under it must be removed first too.';

/// The toast for a refused delete, by the presenter's reason.
String accountDeleteError(StateError e) => switch (e.message) {
      'has_sub_accounts' =>
        'Remove all sub-accounts first before deleting this account.',
      'has_transactions' =>
        'This account has transactions or bills linked to it. '
            'Delete or reassign them first.',
      _ => 'Could not delete account: ${e.message}',
    };
