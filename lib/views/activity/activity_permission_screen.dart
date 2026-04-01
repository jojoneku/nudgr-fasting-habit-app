import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../app_colors.dart';
import '../../presenters/activity_presenter.dart';
import 'activity_screen.dart';

class ActivityPermissionScreen extends StatelessWidget {
  final ActivityPresenter presenter;

  const ActivityPermissionScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TRAINING GROUNDS')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 24),
              Text(
                'Connect Health Connect',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Training Grounds reads your daily steps from Health Connect to track your physical discipline and award AGI points.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _BenefitRow(
                icon: Icons.emoji_events_outlined,
                label: '+25 XP when you hit your daily step goal',
              ),
              const SizedBox(height: 12),
              _BenefitRow(
                icon: MdiIcons.flash,
                label: '+1 AGI every 5 consecutive days goal met',
              ),
              const SizedBox(height: 12),
              _BenefitRow(
                icon: Icons.lock_outline,
                label: 'Read-only — we never write to Health Connect',
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: presenter,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: presenter.isLoading
                          ? null
                          : () => _grantPermission(context),
                      icon: presenter.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Connect Health Connect'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _skipToManual(context),
                      child: Text(
                        'Use manual entry instead',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
        ),
      ],
    );
  }
}
