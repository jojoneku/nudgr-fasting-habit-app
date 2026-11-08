/// The account form's option lists and field validators, shared by the mobile
/// `AccountSetupView` and the web v2 Setup page and account form (Plan 071,
/// Phase 1). Before this, each app kept a private copy.
library;

import 'package:intermittent_fasting/models/finance/financial_account.dart';

/// Validator for optional currency fields: blank is allowed (treated as 0 or
/// unset on submit), but a non-empty value must parse cleanly so malformed
/// input like "1.2.3" is rejected up front instead of silently coerced to 0.
String? optionalAmountValidator(String? v) {
  final raw = (v ?? '').replaceAll(',', '').trim();
  if (raw.isEmpty) return null;
  final parsed = double.tryParse(raw);
  if (parsed == null) return 'Enter a valid number';
  if (parsed < 0) return 'Must be 0 or more';
  return null;
}

/// Account color swatch options — offered by the mobile
/// `AccountSetupView` and the web account form. User-chosen account colors are data, not theme tokens, so the
/// literal hex values are intentional.
const List<String> kAccountColorOptions = [
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
const List<AccountCategory> kTopLevelAccountCategories = [
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
const List<AccountCategory> kSubAccountCategories = [
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.timeDeposit,
];

/// Asset-side types offered for quick switching on a top-level row. Credit
/// (liability) types are excluded: converting to or from a liability flips
/// the balance's meaning and needs a credit limit, so that stays in the form.
const List<AccountCategory> kTopLevelSwitchable = [
  AccountCategory.bank,
  AccountCategory.ewallet,
  AccountCategory.cash,
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.investment,
  AccountCategory.custodian,
];

/// Pocket types offered for quick switching on a sub-account row.
const List<AccountCategory> kSubSwitchable = [
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.timeDeposit,
];

/// Required, strictly positive peso amount (the fixed minimum payment).
String? positiveAmountValidator(String? v) {
  final parsed = double.tryParse((v ?? '').replaceAll(',', '').trim());
  if (parsed == null || parsed <= 0) return 'Enter an amount above ₱0';
  return null;
}

/// Parses a currency field, ignoring thousands separators. Null when blank
/// or malformed.
double? parseAmount(String text) =>
    double.tryParse(text.replaceAll(',', '').trim());
