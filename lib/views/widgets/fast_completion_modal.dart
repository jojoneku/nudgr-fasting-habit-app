import 'package:flutter/material.dart';
import '../../app_colors.dart';

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
      backgroundColor: Colors.transparent,
      builder: (_) => FastCompletionModal(data: data, onDismiss: onDismiss),
    );
  }

  @override
  State<FastCompletionModal> createState() => _FastCompletionModalState();
}

class _FastCompletionModalState extends State<FastCompletionModal>
    with SingleTickerProviderStateMixin {
  final TextEditingController _noteController = TextEditingController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  FastCompletionData get data => widget.data;
  Color get _accentColor =>
      data.wasSuccess ? AppColors.secondary : AppColors.danger;

  String _formatDuration(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: _accentColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withValues(alpha: 0.15),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                const SizedBox(height: 20),
                _buildStatusBadge(),
                const SizedBox(height: 24),
                _buildDurationDisplay(),
                const SizedBox(height: 24),
                _buildStatRow(),
                const SizedBox(height: 24),
                _buildNoteField(),
                const SizedBox(height: 20),
                _buildDismissButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.neutral.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildStatusBadge() => AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _accentColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                data.wasSuccess ? Icons.verified_rounded : Icons.cancel_rounded,
                color: _accentColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                data.wasSuccess ? 'FAST COMPLETE' : 'FAST ENDED EARLY',
                style: TextStyle(
                  color: _accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildDurationDisplay() => Text(
        _formatDuration(data.durationHours),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 52,
          fontWeight: FontWeight.bold,
          height: 1.0,
          letterSpacing: -1,
        ),
      );

  Widget _buildStatRow() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatTile(
            icon: Icons.bolt,
            iconColor: AppColors.gold,
            label: 'XP EARNED',
            value: '+${data.xpEarned}',
            valueColor: AppColors.gold,
          ),
          _buildDivider(),
          _buildStatTile(
            icon: data.hpChange >= 0
                ? Icons.favorite_rounded
                : Icons.heart_broken_rounded,
            iconColor:
                data.hpChange >= 0 ? AppColors.success : AppColors.danger,
            label: 'HP CHANGE',
            value:
                data.hpChange >= 0 ? '+${data.hpChange}' : '${data.hpChange}',
            valueColor:
                data.hpChange >= 0 ? AppColors.success : AppColors.danger,
          ),
          _buildDivider(),
          _buildStatTile(
            icon: Icons.local_fire_department_rounded,
            iconColor: AppColors.danger,
            label: 'STREAK',
            value: '${data.currentStreak} days',
            valueColor: AppColors.textPrimary,
          ),
        ],
      );

  Widget _buildStatTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) =>
      Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
        ],
      );

  Widget _buildDivider() => Container(
        width: 1,
        height: 48,
        color: AppColors.neutral.withValues(alpha: 0.2),
      );

  Widget _buildNoteField() => TextField(
        controller: _noteController,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Add a note to this fast… (optional)',
          hintStyle: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.6),
              fontSize: 14),
          filled: true,
          fillColor: AppColors.background.withValues(alpha: 0.6),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: AppColors.neutral.withValues(alpha: 0.2), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: AppColors.neutral.withValues(alpha: 0.2), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: _accentColor.withValues(alpha: 0.6), width: 1),
          ),
        ),
        maxLines: 2,
      );

  Widget _buildDismissButton() => SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: () async {
            final note = _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim();
            Navigator.pop(context);
            await widget.onDismiss?.call(note);
          },
          style: FilledButton.styleFrom(
            backgroundColor: _accentColor,
            foregroundColor: AppColors.textPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          ),
          child: const Text(
            'ARISE',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2),
          ),
        ),
      );
}
