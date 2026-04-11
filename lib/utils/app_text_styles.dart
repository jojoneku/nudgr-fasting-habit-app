import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTextStyles {
  /// Monospace font for all financial/numeric displays in Treasury.
  static TextStyle mono({TextStyle? textStyle}) =>
      GoogleFonts.robotoMono(textStyle: textStyle);
}
