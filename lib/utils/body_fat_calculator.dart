import 'dart:math';

double? estimateBodyFatPercent({
  required String sex,
  required double heightCm,
  required double waistCm,
  required double neckCm,
  double? hipsCm,
}) {
  if (waistCm <= neckCm) return null;
  if (heightCm <= 0) return null;

  // US Navy formula — original constants are for inches; convert first.
  const cmToIn = 1 / 2.54;
  final hIn = heightCm * cmToIn;
  final wIn = waistCm * cmToIn;
  final nIn = neckCm * cmToIn;

  double bf;
  if (sex == 'female') {
    if (hipsCm == null) return null;
    final sum = wIn + hipsCm * cmToIn - nIn;
    if (sum <= 0) return null;
    bf = 163.205 * log(sum) / ln10 - 97.684 * log(hIn) / ln10 - 78.387;
  } else {
    final diff = wIn - nIn;
    if (diff <= 0) return null;
    bf = 86.010 * log(diff) / ln10 - 70.041 * log(hIn) / ln10 + 36.76;
  }

  return bf.clamp(3.0, 60.0);
}
