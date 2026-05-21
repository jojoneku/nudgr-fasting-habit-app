import 'package:flutter/material.dart';
import '../app_colors.dart';

enum EstimationSource {
  db,
  personalDict,

  /// Cloud AI (Bedrock Haiku) either picked from DB candidates or estimated
  /// macros from its own knowledge for out-of-DB foods. Plan 027.
  cloudAi,

  /// On-device AI (Qwen) either picked from DB candidates or estimated.
  /// Plan 027. Reserved for the on-device-parity work; legacy code may still
  /// use [aiPerItem] until migrated.
  localAi,

  /// Legacy generic AI tag. New code should prefer [cloudAi] or [localAi].
  aiPerItem,
  keywordDensity,
  userManual;

  bool get isTrusted => switch (this) {
        EstimationSource.db ||
        EstimationSource.personalDict ||
        EstimationSource.userManual ||
        EstimationSource.cloudAi =>
          true,
        EstimationSource.localAi ||
        EstimationSource.aiPerItem ||
        EstimationSource.keywordDensity =>
          false,
      };

  String get badge => switch (this) {
        EstimationSource.db => 'DB',
        EstimationSource.personalDict => 'You',
        EstimationSource.cloudAi => 'Cloud',
        EstimationSource.localAi => 'Local AI',
        EstimationSource.aiPerItem => 'AI~',
        EstimationSource.keywordDensity => '~',
        EstimationSource.userManual => 'Set',
      };

  static EstimationSource fromJson(String? value) => switch (value) {
        'personalDict' => EstimationSource.personalDict,
        'cloudAi' => EstimationSource.cloudAi,
        'localAi' => EstimationSource.localAi,
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
      EstimationSource.cloudAi => cs.primary,
      EstimationSource.localAi => cs.tertiary,
      EstimationSource.aiPerItem => context.appColors.gold,
      EstimationSource.keywordDensity => cs.error,
    };
  }
}
