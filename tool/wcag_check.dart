import 'dart:math' as math;

double toLinear(int c8) {
  final s = c8 / 255.0;
  return s <= 0.04045
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double luminance(int r, int g, int b) =>
    0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b);

double contrastRatio(double l1, double l2) {
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

(int, int, int) rgb(int hex) =>
    ((hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF);

String grade(double cr, {bool ui = false}) {
  final pass = ui ? 3.0 : 4.5;
  final passAAA = ui ? 4.5 : 7.0;
  if (cr >= passAAA) return 'AAA ✓';
  if (cr >= pass) return 'AA  ✓';
  return 'FAIL ✗  (need ≥ ${pass.toStringAsFixed(1)}:1)';
}

void check(String label, int fg, int bg, {bool ui = false}) {
  final (fr, fg2, fb) = rgb(fg);
  final (br, bg2, bb) = rgb(bg);
  final cr = contrastRatio(luminance(fr, fg2, fb), luminance(br, bg2, bb));
  final tag = ui ? '[UI 3:1]' : '[text]  ';
  print(
      '  $tag ${label.padRight(48)} ${cr.toStringAsFixed(2).padLeft(5)}:1  ${grade(cr, ui: ui)}');
}

void section(String title) {
  print('\n── $title');
}

void main() {
  // ── Dark mode (AppColors) ──────────────────────────────────────────────────
  const dBg = 0x0A0E14;
  const dSurf = 0x1C2128;
  const dTPri = 0xFFFFFF;
  const dTSec = 0x94A3B8;
  const dPri = 0x29B6F6;
  const dAcc = 0x26C6DA;
  const dSec = 0x4DD0E1;
  const dSucc = 0x66BB6A;
  const dDang = 0xEF5350;
  const dGold = 0xFFCA28;

  // ── Light mode (AppColorsLight) ────────────────────────────────────────────
  const lBg = 0xF8FAFC;
  const lSurf = 0xFFFFFF;
  const lSurfV = 0xEFF3F8;
  const lTPri = 0x0F1923;
  const lTSec = 0x4A5568;
  const lPri = 0x0174B2; // was 0288D1
  const lSec = 0x007A85; // was 00838F
  const lErr = 0xD32F2F;
  const lSucc = 0x2E7D32; // was 388E3C
  const lGold = 0xF9A825;

  section('DARK — text on background #0A0E14');
  check('textPrimary  (#FFFFFF)', dTPri, dBg);
  check('textSecondary (#94A3B8)', dTSec, dBg);
  check('primary (#29B6F6)', dPri, dBg);
  check('accent (#26C6DA)', dAcc, dBg);
  check('secondary (#4DD0E1)', dSec, dBg);
  check('success (#66BB6A)', dSucc, dBg);
  check('danger/error (#EF5350)', dDang, dBg);
  check('gold (#FFCA28)', dGold, dBg);

  section('DARK — text on surface #1C2128');
  check('textPrimary  (#FFFFFF)', dTPri, dSurf);
  check('textSecondary (#94A3B8)', dTSec, dSurf);
  check('primary (#29B6F6)', dPri, dSurf);
  check('accent (#26C6DA)', dAcc, dSurf);
  check('secondary (#4DD0E1)', dSec, dSurf);
  check('success (#66BB6A)', dSucc, dSurf);
  check('danger/error (#EF5350)', dDang, dSurf);
  check('gold (#FFCA28)', dGold, dSurf);

  section('LIGHT — text on background #F8FAFC');
  check('textPrimary  (#0F1923)', lTPri, lBg);
  check('textSecondary (#4A5568)', lTSec, lBg);
  check('primary (#0174B2)', lPri, lBg);
  check('secondary (#007A85)', lSec, lBg);
  check('error (#D32F2F)', lErr, lBg);
  check('success (#2E7D32)', lSucc, lBg);
  check('gold (#F9A825)', lGold, lBg);

  section('LIGHT — text on surface #FFFFFF');
  check('textPrimary  (#0F1923)', lTPri, lSurf);
  check('textSecondary (#4A5568)', lTSec, lSurf);
  check('primary (#0174B2)', lPri, lSurf);
  check('secondary (#007A85)', lSec, lSurf);
  check('error (#D32F2F)', lErr, lSurf);
  check('success (#2E7D32)', lSucc, lSurf);
  check('gold (#F9A825) — decorative', lGold, lSurf, ui: true);

  section('LIGHT — text on surfaceVariant #EFF3F8');
  check('textPrimary  (#0F1923)', lTPri, lSurfV);
  check('textSecondary (#4A5568)', lTSec, lSurfV);
  check('primary (#0174B2)', lPri, lSurfV);

  section('DARK — UI components on background (3:1 threshold)');
  check('primary (#29B6F6)', dPri, dBg, ui: true);
  check('accent (#26C6DA)', dAcc, dBg, ui: true);
  check('secondary (#4DD0E1)', dSec, dBg, ui: true);
  check('success (#66BB6A)', dSucc, dBg, ui: true);
  check('danger (#EF5350)', dDang, dBg, ui: true);
  check('gold (#FFCA28)', dGold, dBg, ui: true);

  section('LIGHT — UI components on background (3:1 threshold)');
  check('primary (#0174B2)', lPri, lBg, ui: true);
  check('secondary (#007A85)', lSec, lBg, ui: true);
  check('error (#D32F2F)', lErr, lBg, ui: true);
  check('success (#2E7D32)', lSucc, lBg, ui: true);
  check('gold (#F9A825)', lGold, lBg, ui: true);
}
