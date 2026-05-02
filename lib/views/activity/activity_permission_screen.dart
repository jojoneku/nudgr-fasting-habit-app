import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../app_colors.dart';
import '../../presenters/activity_presenter.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../widgets/system/system.dart';
import 'activity_screen.dart';

class ActivityPermissionScreen extends StatelessWidget {
  final ActivityPresenter presenter;

  const ActivityPermissionScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Training Grounds',
      padding: EdgeInsets.zero,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Icon(
                  MdiIcons.heartPulse,
                  size: 72,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Connect Health Connect',
                style: AppTextStyles.headlineSmall.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Training Grounds reads your daily steps from Health Connect to track your physical discipline and award AGI points.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              const _BenefitRow(
                icon: Icons.emoji_events_outlined,
                label: '+25 XP when you hit your daily step goal',
              ),
              const SizedBox(height: 12),
              _BenefitRow(
                icon: MdiIcons.flash,
                label: '+1 AGI every 5 consecutive days goal met',
              ),
              const SizedBox(height: 12),
              const _BenefitRow(
                icon: Icons.lock_outline,
                label: 'Read-only — we never write to Health Connect',
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: presenter,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppPrimaryButton(
                      leading: Icons.health_and_safety_outlined,
                      label: 'Connect Health Connect',
                      isLoading: presenter.isLoading,
                      onPressed: presenter.isLoading
                          ? null
                          : () => _grantPermission(context),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppSecondaryButton(
                      label: 'Use manual entry instead',
                      onPressed: () => _skipToManual(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _grantPermission(BuildContext context) async {
    await presenter.requestHealthPermission();
    if (!context.mounted) return;
    if (presenter.hasHealthPermission) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ActivityScreen(presenter: presenter),
        ),
      );
    }
  }

  void _skipToManual(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityScreen(presenter: presenter),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BenefitRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.success, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      ],
    );
  }
}
