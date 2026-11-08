import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// Plan 071 Phase 0.3: a negative balance reads `−₱1,234.00` (typographic
/// minus before the peso sign) everywhere, never `₱-1,234.00`.
void main() {
  test('negative amounts put a typographic minus before the peso sign', () {
    expect(formatPesoMinus(-1234), '−₱1,234.00');
    expect(formatPesoMinus(-0.5), '−₱0.50');
  });

  test('zero and positive amounts carry no sign', () {
    expect(formatPesoMinus(0), '₱0.00');
    expect(formatPesoMinus(1234.5), '₱1,234.50');
  });

  test('never renders the ₱- form', () {
    for (final v in [-1.0, -999.99, -1000000.0]) {
      expect(formatPesoMinus(v), isNot(contains('₱-')));
    }
  });
}
