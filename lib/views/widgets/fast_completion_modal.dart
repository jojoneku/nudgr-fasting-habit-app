import 'package:flutter/material.dart';
import '../../utils/app_spacing.dart';
import 'system/system.dart';

class FastCompletionData {
  final int xpEarned;
  final int hpChange;
  final double durationHours;
  final bool wasSuccess;
  final int currentStreak;

  const FastCompletionData({
    required this.xpEarned,
    required this.hpChange,
    required this.durationHours,
    required this.wasSuccess,
    required this.currentStreak,
  });
}

class FastCompletionModal extends StatefulWidget {
  final FastCompletionData data;
  final Future<void> Function(String? note)? onDismiss;

  const FastCompletionModal({
    super.key,
    required this.data,
    this.onDismiss,
  });

  static Future<void> show(
    BuildContext context,
    FastCompletionData data, {
    Future<void> Function(String? note)? onDismiss,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FastCompletionModal(data: data, onDismiss: onDismiss),
    );
  }

  @override
  State<FastCompletionModal> createState() => _FastCompletionModalState();
}

class _FastCompletionModalState extends State<FastCompletionModal> {
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  FastCompletionData get data => widget.data;

  String _formatDuration(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = data.wasSuccess
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdGenerous),
              // Status pill
              AppStatPill(
                icon: data.wasSuccess
                    ? Icons.verified_rounded
                    : Icons.cancel_rounded,
                value: data.wasSuccess ? 'Fast complete' : 'Fast ended early',
                color: data.wasSuccess
                    ? AppStatColor.success
                    : AppStatColor.error,
              ),
              const SizedBox(height: AppSpacing.mdGenerous),
              // Duration
              AppNumberDisplay(
                value: _formatDuration(data.durationHours),
                size: AppNumberSize.display,
                color: accentColor,
              ),
              const SizedBox(height: AppSpacing.mdGenerous),
              // Stat row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  AppStatPill(
                    icon: Icons.bolt,
                    label: 'XP',
                    value: '+${data.xpEarned}',
                    color: AppStatColor.warning,
                  ),
                  AppStatPill(
                    icon: data.hpChange >= 0
                        ? Icons.favorite_rounded
                        : Icons.heart_broken_rounded,
                    label: 'HP',
                    value: data.hpChange >= 0
                        ? '+${data.hpChange}'
                        : '${data.hpChange}',
                    color: data.hpChange >= 0
                        ? AppStatColor.success
                        : AppStatColor.error,
                  ),
                  AppStatPill(
                    icon: Icons.local_fire_department_rounded,
                    label: 'Streak',
                    value: '${data.currentStreak}d',
                    color: AppStatColor.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.mdGenerous),
              // Note field
              AppTextField(
                controller: _noteController,
                hint: 'Add a note… (optional)',
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              // Done button
              AppPrimaryButton(
                label: 'Done',
                onPressed: () async {
                  final note = _noteController.text.trim().isEmpty
                      ? null
                      : _noteController.text.trim();
                  Navigator.pop(context);
                  await widget.onDismiss?.call(note);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
