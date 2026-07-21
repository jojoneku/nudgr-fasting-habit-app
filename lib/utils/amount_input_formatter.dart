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

/// Allows a simple arithmetic expression — digits, a decimal point, and the
/// four operators (`+ - * /`, plus `×`/`÷`) — so the "calculator" amount field
/// accepts input like `285+15`. Blocks letters and other symbols so
/// [evalAmountExpression] always receives clean input.
class CalcAmountInputFormatter extends TextInputFormatter {
  const CalcAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (RegExp(r'[^\d.+\-*/×÷]').hasMatch(text)) return oldValue;
    return newValue;
  }
}

/// Drop-in `inputFormatters` list for the calculator-style amount field.
const calcAmountInputFormatters = <TextInputFormatter>[
  CalcAmountInputFormatter()
];

/// Evaluates a simple `+ - × ÷` expression with normal operator precedence
/// (`* /` before `+ -`), left-to-right. A plain number returns itself, so
/// "just type the amount" is unchanged. Returns null on malformed input or
/// division by zero — callers treat that as "invalid amount".
double? evalAmountExpression(String input) {
  final s = input.replaceAll('×', '*').replaceAll('÷', '/').replaceAll(' ', '');
  if (s.isEmpty) return null;

  // Tokenize into numbers and binary operators; reject leading/trailing or
  // doubled operators (they'd be malformed for a positive amount).
  final tokens = <String>[];
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    if (RegExp(r'[\d.]').hasMatch(ch)) {
      buf.write(ch);
    } else if ('+-*/'.contains(ch)) {
      if (buf.isEmpty) return null;
      tokens.add(buf.toString());
      buf.clear();
      tokens.add(ch);
    } else {
      return null;
    }
  }
  if (buf.isEmpty) return null;
  tokens.add(buf.toString());

  // Shunting-yard → RPN.
  int prec(String o) => (o == '*' || o == '/') ? 2 : 1;
  final output = <String>[];
  final ops = <String>[];
  for (final t in tokens) {
    if (t.length == 1 && '+-*/'.contains(t)) {
      while (ops.isNotEmpty && prec(ops.last) >= prec(t)) {
        output.add(ops.removeLast());
      }
      ops.add(t);
    } else {
      output.add(t);
    }
  }
  while (ops.isNotEmpty) {
    output.add(ops.removeLast());
  }

  // Evaluate RPN.
  final stack = <double>[];
  for (final t in output) {
    if (t.length == 1 && '+-*/'.contains(t)) {
      if (stack.length < 2) return null;
      final b = stack.removeLast();
      final a = stack.removeLast();
      switch (t) {
        case '+':
          stack.add(a + b);
        case '-':
          stack.add(a - b);
        case '*':
          stack.add(a * b);
        case '/':
          if (b == 0) return null;
          stack.add(a / b);
      }
    } else {
      final v = double.tryParse(t);
      if (v == null) return null;
      stack.add(v);
    }
  }
  if (stack.length != 1) return null;
  final result = stack.first;
  if (result.isNaN || result.isInfinite) return null;
  return result;
}

/// Formats an evaluated amount back into the field: whole numbers show without
/// decimals, otherwise up to 2 places with trailing zeros trimmed.
String formatEvaluatedAmount(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
