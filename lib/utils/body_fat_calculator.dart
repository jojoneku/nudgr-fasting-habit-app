import 'dart:math';

/// US Navy circumference method (Hodgdon & Beckett 1984).
/// Original constants are for inches; we convert cm → in internally.
double? estimateBodyFatPercent({
  required String sex,
  required double heightCm,
  required double waistCm,
  required double neckCm,
  double? hipsCm,
}) {
  if (waistCm <= neckCm) return null;
  if (heightCm <= 0) return null;

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

/// Deurenberg BMI-derived body fat % estimate (Deurenberg et al. 1991).
/// BF% = 1.20 × BMI + 0.23 × age − 10.8 × sex_factor − 5.4
/// (sex_factor: 1 = male, 0 = female)
double? estimateBodyFatPercentBmi({
  required String sex,
  required double heightCm,
  required double weightKg,
  required int ageYears,
}) {
  if (heightCm <= 0 || weightKg <= 0 || ageYears <= 0) return null;
  final heightM = heightCm / 100;
  final bmi = weightKg / (heightM * heightM);
  final sexFactor = sex == 'male' ? 1.0 : 0.0;
  final bf = (1.20 * bmi) + (0.23 * ageYears) - (10.8 * sexFactor) - 5.4;
  return bf.clamp(3.0, 60.0);
}
