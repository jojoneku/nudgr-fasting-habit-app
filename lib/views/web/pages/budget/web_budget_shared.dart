import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:intermittent_fasting/app_colors.dart';

/// The accent a budget group is drawn in — its table dot, its donut slice,
/// its legend line and the fill of its rows' Used bars. Cycles the domain
/// accents in group order so the three defaults read blue · purple · gold as
/// on the canvas, and a fourth, fifth or sixth custom group still gets a
/// colour of its own before the cycle repeats.
Color webBudgetGroupColor(BuildContext context, int index) {
  final cs = Theme.of(context).colorScheme;
  final a = context.appColors;
  final palette = [cs.primary, a.weight, a.treasury, a.food, a.move, a.bills];
  return palette[index % palette.length];
}

/// Whole-peso figure for the places the canvas drops the centavos — status
/// pills ("Over by ₱76") and the remaining cell ("₱76 over") — so the pill
/// stays one line in a 140 px column. Totals keep `formatPeso`.
String formatPesoWhole(double amount) {
  final formatter = NumberFormat('#,##0', 'en_PH');
  return '₱${formatter.format(amount.round())}';
}
