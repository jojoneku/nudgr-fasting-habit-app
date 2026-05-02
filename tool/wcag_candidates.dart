import 'dart:math' as math;

double toLinear(int c8) {
  final s = c8 / 255.0;
  return s <= 0.04045
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double lum(int r, int g, int b) =>
    0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b);

double cr(int fg, int bg) {
  final (fr, fg2, fb) = ((fg >> 16) & 0xFF, (fg >> 8) & 0xFF, fg & 0xFF);
  final (br, bg2, bb) = ((bg >> 16) & 0xFF, (bg >> 8) & 0xFF, bg & 0xFF);
  final lf = lum(fr, fg2, fb);
  final lb = lum(br, bg2, bb);
  final lighter = lf > lb ? lf : lb;
  final darker = lf > lb ? lb : lf;
  return (lighter + 0.05) / (darker + 0.05);
}

const bg = 0xF8FAFC; // light background
const surf = 0xFFFFFF; // surface
const surfV = 0xEFF3F8; // surfaceVariant

void row(String label, int color) {
  final cbg = cr(color, bg);
  final cs = cr(color, surf);
  final csv = cr(color, surfV);
  final pass = (r) => r >= 4.5 ? '✓' : '✗';
  print(
      '  ${label.padRight(22)} bg:${cbg.toStringAsFixed(2).padLeft(5)} ${pass(cbg)}'
      '  surf:${cs.toStringAsFixed(2).padLeft(5)} ${pass(cs)}'
      '  surfV:${csv.toStringAsFixed(2).padLeft(5)} ${pass(csv)}');
}

void main() {
  print('Candidate colors — need ≥ 4.5:1 on all three surfaces');
  print('${' '.padLeft(24)}bg      surf      surfV');

  print('\n── PRIMARY (current: #0288D1 = 3.69/3.86/3.46 all fail)');
  row('#0288D1 (current)', 0x0288D1);
  row('#0277BD (L700)', 0x0277BD);
  row('#0174B2', 0x0174B2);
  row('#016CB3', 0x016CB3);
  row('#0270B5', 0x0270B5);
  row('#0069B3', 0x0069B3);
  row('#01579B (L900)', 0x01579B);

  print('\n── SECONDARY (current: #00838F = 4.32/4.52/4.06 bg+surfV fail)');
  row('#00838F (current)', 0x00838F);
  row('#007A85', 0x007A85);
  row('#006E78', 0x006E78);
  row('#00747F', 0x00747F);

  print('\n── SUCCESS (current: #388E3C = 3.93/4.12/3.69 all fail)');
  row('#388E3C (current)', 0x388E3C);
  row('#2E7D32 (G800)', 0x2E7D32);
  row('#2D7A31', 0x2D7A31);
  row('#2A6E2D', 0x2A6E2D);

  print('\n── GOLD (#F9A825 = 1.88 — yellow on white never passes 4.5:1)');
  row('#F9A825 (current)', 0xF9A825);
  row('#E65100 (deepOrng)', 0xE65100);
  row('#EF6C00 (orng700)', 0xEF6C00);
  print(
      '  (gold used only as fills/tints, not body text → no text fix needed)');
}
