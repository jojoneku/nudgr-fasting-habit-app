import 'package:flutter/material.dart';

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

  Color get badgeColor => switch (this) {
        EstimationSource.db ||
        EstimationSource.personalDict ||
        EstimationSource.userManual =>
          const Color(0xFF6B7280),
        EstimationSource.aiPerItem => const Color(0xFFF59E0B),
        EstimationSource.keywordDensity => const Color(0xFFEF4444),
      };

  static EstimationSource fromJson(String? value) => switch (value) {
        'personalDict' => EstimationSource.personalDict,
        'aiPerItem' => EstimationSource.aiPerItem,
        'keywordDensity' => EstimationSource.keywordDensity,
        'userManual' => EstimationSource.userManual,
        _ => EstimationSource.db,
      };
}
