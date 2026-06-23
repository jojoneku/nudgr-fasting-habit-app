import 'package:flutter/services.dart';

/// Restricts a text field to a well-formed peso amount: digits plus at most one
/// decimal point with no more than two fractional digits. Rejects malformed
/// input like "1.2.3" or "12.345" that `double.tryParse` would silently fail —
/// the user gets immediate feedback instead of a misleading "must be > 0" error
/// on submit.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // Only digits and a dot are allowed at all.
    if (RegExp(r'[^\d.]').hasMatch(text)) return oldValue;
    // At most one decimal point.
    if ('.'.allMatches(text).length > 1) return oldValue;
    // At most two fractional digits.
    final dot = text.indexOf('.');
    if (dot != -1 && text.length - dot - 1 > 2) return oldValue;
    return newValue;
  }
}

/// Drop-in `inputFormatters` list for peso amount fields.
const amountInputFormatters = <TextInputFormatter>[AmountInputFormatter()];
