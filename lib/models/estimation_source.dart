import 'package:flutter/material.dart';
import '../app_colors.dart';

enum EstimationSource {
  db,
  personalDict,

  /// Cloud AI (Bedrock Haiku) either picked from DB candidates or estimated
  /// macros from its own knowledge for out-of-DB foods. Plan 027.
  cloudAi,

  /// Cloud AI macro estimate that was synthesised from a generic ~2 kcal/g
  /// ratio because the model failed to return macros. The figure is a rough
  /// approximation — shown with a warning badge so users know to verify.
  /// Plan 034 SEV-3.
  cloudAiFallback,

  /// On-device AI (Qwen) either picked from DB candidates or estimated.
  /// Plan 027. Reserved for the on-device-parity work; legacy code may still
  /// use [aiPerItem] until migrated.
  localAi,

  /// Legacy generic AI tag. New code should prefer [cloudAi] or [localAi].
  aiPerItem,
  keywordDensity,
  userManual;

  /// Whether a badge should be shown on the food log item for this source.
  /// DB is the silent baseline; everything else is worth surfacing.
  bool get showBadge => switch (this) {
        EstimationSource.db => false,
        _ => true,
      };

  bool get isTrusted => switch (this) {
        EstimationSource.db ||
        EstimationSource.personalDict ||
        EstimationSource.userManual ||
        EstimationSource.cloudAi =>
          true,
        EstimationSource.cloudAiFallback ||
        EstimationSource.localAi ||
        EstimationSource.aiPerItem ||
        EstimationSource.keywordDensity =>
          false,
      };

  String get badge => switch (this) {
        EstimationSource.db => 'DB',
        EstimationSource.personalDict => 'You',
        EstimationSource.cloudAi => 'Cloud',
        EstimationSource.cloudAiFallback => 'Cloud~',
        EstimationSource.localAi => 'Local AI',
        EstimationSource.aiPerItem => 'AI~',
        EstimationSource.keywordDensity => '~',
        EstimationSource.userManual => 'Set',
      };

  static EstimationSource fromJson(String? value) => switch (value) {
        'personalDict' => EstimationSource.personalDict,
        'cloudAi' => EstimationSource.cloudAi,
        'cloudAiFallback' => EstimationSource.cloudAiFallback,
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
      EstimationSource.cloudAiFallback => cs.error,
      EstimationSource.localAi => cs.tertiary,
      EstimationSource.aiPerItem => context.appColors.gold,
      EstimationSource.keywordDensity => cs.error,
    };
  }
}
