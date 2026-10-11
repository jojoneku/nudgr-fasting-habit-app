/// The account form's option lists and field validators, shared by the v2
/// Setup page and account form (Plan 063, Phase 8). They were private to
/// `web_account_form_dialog.dart` and `web_setup_page.dart`; when those two
/// files go in Phase 11, this is the one copy that stays.
library;

import 'package:intermittent_fasting/models/finance/financial_account.dart';

/// Account color swatch options — the same list the mobile `AccountSetupView`
/// offers. User-chosen account colors are data, not theme tokens, so the
/// literal hex values are intentional.
const List<String> kWebAccountColorOptions = [
  '#7C3AED',
  '#2563EB',
  '#059669',
  '#D97706',
  '#DC2626',
  '#0891B2',
  '#9333EA',
  '#64748B',
];

/// Types a top-level account can be given in the form.
const List<AccountCategory> kWebTopLevelAccountCategories = [
  AccountCategory.bank,
  AccountCategory.ewallet,
  AccountCategory.cash,
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.creditCard,
  AccountCategory.creditLine,
  AccountCategory.bnpl,
  AccountCategory.investment,
  AccountCategory.custodian,
];

/// Types a pocket under a parent account can be given.
const List<AccountCategory> kWebSubAccountCategories = [
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.timeDeposit,
];

/// Asset-side types offered for quick switching on a top-level row. Credit
/// (liability) types are excluded: converting to or from a liability flips
/// the balance's meaning and needs a credit limit, so that stays in the form.
const List<AccountCategory> kWebTopLevelSwitchable = [
  AccountCategory.bank,
  AccountCategory.ewallet,
  AccountCategory.cash,
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.investment,
  AccountCategory.custodian,
];

/// Pocket types offered for quick switching on a sub-account row.
const List<AccountCategory> kWebSubSwitchable = [
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.timeDeposit,
];

/// Validator for optional currency fields: blank is allowed (treated as 0 or
/// unset on submit), but a non-empty value must parse cleanly so malformed
/// input like "1.2.3" is rejected up front instead of silently coerced to 0.
String? webOptionalAmountValidator(String? v) {
  final raw = (v ?? '').replaceAll(',', '').trim();
  if (raw.isEmpty) return null;
  final parsed = double.tryParse(raw);
  if (parsed == null) return 'Enter a valid number';
  if (parsed < 0) return 'Must be 0 or more';
  return null;
}

/// Required, strictly positive peso amount (the fixed minimum payment).
String? webPositiveAmountValidator(String? v) {
  final parsed = double.tryParse((v ?? '').replaceAll(',', '').trim());
  if (parsed == null || parsed <= 0) return 'Enter an amount above ₱0';
  return null;
}

/// Parses a currency field, ignoring thousands separators. Null when blank
/// or malformed.
double? webParseAmount(String text) =>
    double.tryParse(text.replaceAll(',', '').trim());
