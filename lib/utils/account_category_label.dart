import 'package:intermittent_fasting/models/finance/financial_account.dart';

/// Single source of the human-readable label for an [AccountCategory], on the
/// web Treasury pages and in the mobile app. The 11-arm switch used to be
/// copy-pasted in several places (Plan 052 D1 for web, Plan 071 Phase 1 for
/// mobile), and the copies drifted ("Time deposit" vs "Time Deposit").
extension AccountCategoryLabel on AccountCategory {
  String get label => switch (this) {
        AccountCategory.bank => 'Bank',
        AccountCategory.ewallet => 'eWallet',
        AccountCategory.cash => 'Cash',
        AccountCategory.savings => 'Savings',
        AccountCategory.goal => 'Goal',
        AccountCategory.timeDeposit => 'Time Deposit',
        AccountCategory.creditCard => 'Credit Card',
        AccountCategory.creditLine => 'Credit Line',
        AccountCategory.bnpl => 'BNPL',
        AccountCategory.investment => 'Investment',
        AccountCategory.custodian => 'External',
      };
}
