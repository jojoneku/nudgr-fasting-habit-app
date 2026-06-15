import 'package:intermittent_fasting/models/finance/financial_account.dart';

/// Single source of the human-readable label for an [AccountCategory] on the
/// web Treasury pages. Previously this 11-arm switch was copy-pasted in three
/// places (the setup page's category + type labels and the account form),
/// which would silently drift as categories were added. (Plan 052 D1)
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
