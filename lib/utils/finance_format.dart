import 'package:intl/intl.dart';

/// Converts a [DateTime] to a 'YYYY-MM' month key string.
String toMonthKey(DateTime date) => DateFormat('yyyy-MM').format(date);

/// Formats [amount] as Philippine Peso with two decimal places.
/// e.g. 1234.56 → '₱1,234.56'
String formatPeso(double amount) {
  final formatter = NumberFormat('#,##0.00', 'en_PH');
  return '₱${formatter.format(amount)}';
}

/// Like [formatPeso] but with an explicit leading sign and the minus rendered
/// as a typographic '−' before the peso symbol. e.g. 3904 → '+₱3,904.00',
/// -2000 → '−₱2,000.00', 0 → '₱0.00'.
String formatPesoSigned(double amount) {
  if (amount == 0) return formatPeso(0);
  final sign = amount > 0 ? '+' : '−';
  return '$sign${formatPeso(amount.abs())}';
}

/// Formats a 0..1 [fraction] as a percentage. e.g. 0.316 → '32%'.
String formatPercent(double fraction, {int decimals = 0}) =>
    '${(fraction * 100).toStringAsFixed(decimals)}%';

/// Formats [amount] compactly with at most one decimal place.
/// e.g. 1200 → '₱1.2k', 51000 → '₱51k', 1200000 → '₱1.2M'
String formatPesoCompact(double amount) {
  if (amount.abs() >= 1000000) {
    final v = amount / 1000000;
    final s =
        v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return '₱${s}M';
  }
  if (amount.abs() >= 1000) {
    final v = amount / 1000;
    final s =
        v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return '₱${s}k';
  }
  return formatPeso(amount);
}

/// Converts a 'YYYY-MM' month key to a human-readable label.
/// e.g. '2026-03' → 'March 2026'
String monthLabel(String monthKey) {
  final date = DateTime.parse('$monthKey-01');
  return DateFormat('MMMM yyyy').format(date);
}

/// Converts a 'YYYY-MM' month key to a short month label.
/// e.g. '2026-03' → 'Mar'
String monthShortLabel(String monthKey) {
  final date = DateTime.parse('$monthKey-01');
  return DateFormat('MMM').format(date);
}

/// Short month-and-day label for a date. e.g. 2026-08-05 → 'Aug 5'
String monthDayLabel(DateTime date) => DateFormat('MMM d').format(date);

/// Compact label for a month chip/dropdown: the month name alone within the
/// current year (e.g. 'June'), or month + year across years (e.g. "Dec 2025")
/// so the control stays short but never ambiguous.
String monthChipLabel(String monthKey) {
  final date = DateTime.parse('$monthKey-01');
  if (date.year == DateTime.now().year) {
    return DateFormat('MMMM').format(date);
  }
  return DateFormat('MMM yyyy').format(date);
}

/// Returns the month key for the month before [monthKey].
/// e.g. '2026-03' → '2026-02', '2026-01' → '2025-12'
String previousMonth(String monthKey) {
  final date = DateTime.parse('$monthKey-01');
  final prev = DateTime(date.year, date.month - 1);
  return toMonthKey(prev);
}

/// Returns the month key for the month after [monthKey].
/// e.g. '2026-03' → '2026-04', '2026-12' → '2027-01'
String nextMonth(String monthKey) {
  final date = DateTime.parse('$monthKey-01');
  final next = DateTime(date.year, date.month + 1);
  return toMonthKey(next);
}
