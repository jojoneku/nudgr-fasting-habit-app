// Validation rules the account form uses on both mobile and web.

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
