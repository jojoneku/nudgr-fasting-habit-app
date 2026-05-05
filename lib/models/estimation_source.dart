import 'package:flutter/material.dart';
import '../app_colors.dart';

enum EstimationSource {
  db,
  personalDict,
  aiPerItem,
  keywordDensity,
  userManual;

  bool get isTrusted => switch (this) {
        EstimationSource.db ||
        EstimationSource.personalDict ||
        EstimationSource.userManual =>
          true,
        EstimationSource.aiPerItem || EstimationSource.keywordDensity => false,
      };

  String get badge => switch (this) {
        EstimationSource.db => 'DB',
        EstimationSource.personalDict => 'You',
        EstimationSource.aiPerItem => 'AI~',
        EstimationSource.keywordDensity => '~',
        EstimationSource.userManual => 'Set',
      };

  static EstimationSource fromJson(String? value) => switch (value) {
        'personalDict' => EstimationSource.personalDict,
        'aiPerItem' => EstimationSource.aiPerItem,
        'keywordDensity' => EstimationSource.keywordDensity,
        'userManual' => EstimationSource.userManual,
        _ => EstimationSource.db,
      };
}

extension EstimationSourceColor on EstimationSource {
  Color badgeColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (this) {
      EstimationSource.db ||
      EstimationSource.personalDict ||
      EstimationSource.userManual =>
        cs.onSurfaceVariant,
      EstimationSource.aiPerItem => context.appColors.gold,
      EstimationSource.keywordDensity => cs.error,
    };
  }
}
