import 'package:flutter/material.dart';
import '../app_colors.dart';

enum FastingPhase {
  sugarBurn(
    label: 'Glycogen Depletion',
    rpgTitle: 'PHASE I',
    minHours: 0,
    color: AppColors.neutral,
    description: 'Body burning stored glucose.',
  ),
  fatBurn(
    label: 'Lipolysis Activated',
    rpgTitle: 'PHASE II',
    minHours: 4,
    color: AppColors.secondary,
    description: 'Fat cells releasing energy.',
  ),
  ketosis(
    label: 'Ketone Mode',
    rpgTitle: 'PHASE III',
    minHours: 8,
    color: Color(0xFFAB47BC), // purple
    description: 'Brain running on ketones.',
  ),
  cellPurge(
    label: 'Cell Purge Protocol',
    rpgTitle: 'PHASE IV',
    minHours: 16,
    color: AppColors.gold,
    description: 'Autophagy fully activated.',
  ),
  immuneForge(
    label: 'Immune Forge',
    rpgTitle: 'PHASE V',
    minHours: 24,
    color: Color(0xFFFF7043), // deep orange
    description: 'Immune system regenerating.',
  ),
  voidTranscendence(
    label: 'Void Transcendence',
    rpgTitle: 'PHASE VI',
    minHours: 36,
    color: AppColors.danger,
    description: 'Stem cell renewal. Maximum purge.',
  );

  final String label;
  final String rpgTitle;
  final int minHours;
  final Color color;
  final String description;

  const FastingPhase({
    required this.label,
    required this.rpgTitle,
    required this.minHours,
    required this.color,
    required this.description,
  });

  static FastingPhase fromElapsedSeconds(int seconds) {
    final hours = seconds / 3600.0;
    if (hours >= 36) return FastingPhase.voidTranscendence;
    if (hours >= 24) return FastingPhase.immuneForge;
    if (hours >= 16) return FastingPhase.cellPurge;
    if (hours >= 8) return FastingPhase.ketosis;
    if (hours >= 4) return FastingPhase.fatBurn;
    return FastingPhase.sugarBurn;
  }
}
