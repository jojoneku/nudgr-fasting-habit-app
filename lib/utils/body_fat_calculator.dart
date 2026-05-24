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

  double bf;
  if (sex == 'female') {
    if (hipsCm == null) return null;
    final sum = waistCm + hipsCm - neckCm;
    if (sum <= 0) return null;
    bf = 163.205 * log(sum) / ln10 -
        97.684 * log(heightCm) / ln10 -
        78.387;
  } else {
    final diff = waistCm - neckCm;
    if (diff <= 0) return null;
    bf = 86.010 * log(diff) / ln10 -
        70.041 * log(heightCm) / ln10 +
        36.76;
  }

  return bf.clamp(3.0, 60.0);
}
