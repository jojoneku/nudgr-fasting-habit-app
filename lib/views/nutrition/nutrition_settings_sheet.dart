import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/meal_slot.dart';
import '../../models/nutrition_goals.dart';
import '../../presenters/ai_coach_presenter.dart';
import '../../presenters/nutrition_presenter.dart';
import 'tdee_setup_screen.dart';
import '../widgets/system/system.dart';

/// Bottom sheet: tracking mode, daily calorie goal, macro targets, TDEE wizard link, overshoot penalty.
Future<void> showNutritionSettingsSheet(
  BuildContext context,
  NutritionPresenter presenter, {
  AiCoachPresenter? aiCoachPresenter,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NutritionSettingsSheet(
      presenter: presenter,
      aiCoachPresenter: aiCoachPresenter,
    ),
  );
}

class _NutritionSettingsSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  final AiCoachPresenter? aiCoachPresenter;
  const _NutritionSettingsSheet({
    required this.presenter,
    this.aiCoachPresenter,
  });

  @override
  State<_NutritionSettingsSheet> createState() =>
      _NutritionSettingsSheetState();
}

class _NutritionSettingsSheetState extends State<_NutritionSettingsSheet> {
  late TrackingMode _mode;
  late int _dailyCalories;
  late double? _protein;
  late double? _carbs;
  late double? _fat;
  late bool _ifSync;
  late bool _overshootPenalty;

  final _calCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final g = widget.presenter.goals;
    _mode = g.mode;
    _dailyCalories = g.dailyCalories;
    _protein = g.proteinGrams;
    _carbs = g.carbsGrams;
    _fat = g.fatGrams;
    _ifSync = g.ifSyncEnabled;
    _overshootPenalty = g.overshootPenaltyEnabled;

    _calCtrl.text = _dailyCalories.toString();
    _proteinCtrl.text = _protein?.toStringAsFixed(0) ?? '';
    _carbsCtrl.text = _carbs?.toStringAsFixed(0) ?? '';
    _fatCtrl.text = _fat?.toStringAsFixed(0) ?? '';
  }

  @override
  void dispose() {
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cal = int.tryParse(_calCtrl.text.trim());
    if (cal == null || cal <= 0) return;

    final goals = NutritionGoals(
      mode: _mode,
      dailyCalories: cal,
      proteinGrams: double.tryParse(_proteinCtrl.text.trim()),
      carbsGrams: double.tryParse(_carbsCtrl.text.trim()),
      fatGrams: double.tryParse(_fatCtrl.text.trim()),
      ifSyncEnabled: _ifSync,
      overshootPenaltyEnabled: _overshootPenalty,
    );
    await widget.presenter.updateGoals(goals);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final isStandard = _mode == TrackingMode.standard;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Settings',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Tracking mode ───────────────────────────────────────
                  Text('Tracking mode',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  ...TrackingMode.values.map((m) => _ModeTile(
                        mode: m,
                        selected: _mode == m,
                        onTap: () => setState(() => _mode = m),
                      )),
                  const SizedBox(height: 20),

                  // ── Simple: manual calorie goal ──────────────────────────
                  if (!isStandard) ...[
                    Text('Daily calorie goal',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: _calCtrl,
                      label: 'kcal / day',
                      hint: 'e.g. 2000',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Standard: TDEE + macros + toggles ───────────────────
                  if (isStandard) ...[
                    _TdeeCard(presenter: widget.presenter),
                    const SizedBox(height: 20),
                    Text('Macro targets (optional, g)',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: AppTextField(
                              controller: _proteinCtrl,
                              label: 'Protein',
                              hint: 'g',
                              keyboardType: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: AppTextField(
                              controller: _carbsCtrl,
                              label: 'Carbs',
                              hint: 'g',
                              keyboardType: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: AppTextField(
                              controller: _fatCtrl,
                              label: 'Fat',
                              hint: 'g',
                              keyboardType: TextInputType.number)),
                    ]),
                    const SizedBox(height: 20),
                    _ToggleRow(
                      label: 'Lock logging during fast',
                      subtitle:
                          'Pause food logging while fasting window is active',
                      value: _ifSync,
                      onChanged: (v) => setState(() => _ifSync = v),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Overshoot penalty (both modes) ──────────────────────
                  _ToggleRow(
                    label: 'Overshoot penalty',
                    subtitle: '−5 HP when you exceed 120% of goal',
                    value: _overshootPenalty,
                    onChanged: (v) => setState(() => _overshootPenalty = v),
                  ),
                  const SizedBox(height: 24),

                  // ── AI Coach download ────────────────────────────────────
                  if (widget.aiCoachPresenter != null) ...[
                    Text('AI Coach',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    _AiCoachDownloadCard(
                        presenter: widget.aiCoachPresenter!),
                    const SizedBox(height: 24),
                  ],

                  AppPrimaryButton(
                    label: 'Save',
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode tile ──────────────────────────────────────────────────────────────────

class _ModeTile extends StatelessWidget {
  final TrackingMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTile(
      {required this.mode, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.1)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(children: [
          Radio<TrackingMode>(
            value: mode,
            groupValue: selected ? mode : null,
            onChanged: (_) => onTap(),
            activeColor: AppColors.gold,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode.label,
                  style: TextStyle(
                    color: selected ? AppColors.gold : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  _modeDescription(mode),
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  String _modeDescription(TrackingMode m) {
    switch (m) {
      case TrackingMode.simple:
        return 'Manual calorie goal — quick and minimal';
      case TrackingMode.standard:
        return 'TDEE goal · optional macros · optional fasting lock';
    }
  }
}

// ── TDEE card ──────────────────────────────────────────────────────────────────

class _TdeeCard extends StatelessWidget {
  final NutritionPresenter presenter;
  const _TdeeCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final profile = presenter.tdeeProfile;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TDEE profile',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          if (profile == null)
            Text(
              'No profile set — tap below to configure',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12),
            )
          else
            AppNumberDisplay(
              value: '${profile.targetCalories}',
              suffix: 'kcal/day',
              size: AppNumberSize.title,
              color: AppColors.gold,
              textAlign: TextAlign.start,
            ),
          if (profile != null) ...[
            const SizedBox(height: 4),
            Text(
              profile.goal.toUpperCase(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.gold,
                side: const BorderSide(color: AppColors.gold, width: 0.8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        TdeeSetupScreen(presenter: presenter)),
              ),
              child: Text(
                profile == null ? 'Set up TDEE' : 'Edit TDEE profile',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Toggle row ─────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;
  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              Text(
                subtitle,
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.gold,
          activeTrackColor: AppColors.gold.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

// ── AI Coach download card ─────────────────────────────────────────────────────

class _AiCoachDownloadCard extends StatelessWidget {
  final AiCoachPresenter presenter;
  const _AiCoachDownloadCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: presenter,
      builder: (_, __) {
        final available = presenter.isModelAvailable;
        final downloading = presenter.isDownloading;
        final progress = presenter.downloadProgress ?? 0;

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('🧠', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Qwen3 0.6B',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          available
                              ? 'Ready — meal parsing & coaching active'
                              : 'On-device · ~586 MB · Private',
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (available)
                    const AppBadge(
                      text: 'Ready',
                      color: AppColors.success,
                      variant: AppBadgeVariant.tonal,
                    ),
                ],
              ),
              if (downloading) ...[
                const SizedBox(height: 14),
                AppLinearProgress(
                  value: progress / 100.0,
                  height: 6,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Downloading...',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11),
                    ),
                    Text(
                      '$progress%',
                      style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ] else if (!available) ...[
                const SizedBox(height: 12),
                AppPrimaryButton(
                  label: 'Download AI Coach',
                  leading: Icons.download_outlined,
                  onPressed: presenter.downloadModel,
                  height: 44,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
