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
  // GlobalKey lets the pinned primaryAction trigger the body's save() while the
  // form state lives inside the body widget.
  final bodyKey = GlobalKey<_NutritionSettingsSheetState>();
  return AppBottomSheet.show<void>(
    context: context,
    title: 'Settings',
    body: _NutritionSettingsSheet(
      key: bodyKey,
      presenter: presenter,
      aiCoachPresenter: aiCoachPresenter,
    ),
    primaryAction: AppPrimaryButton(
      label: 'Save',
      onPressed: () => bodyKey.currentState?.save(),
    ),
  );
}

class _NutritionSettingsSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  final AiCoachPresenter? aiCoachPresenter;
  const _NutritionSettingsSheet({
    super.key,
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

  Future<void> save() async {
    final cal = int.tryParse(_calCtrl.text.trim());
    if (cal == null || cal <= 0) return;

    final isStandard = _mode == TrackingMode.standard;
    // In standard mode macros are owned by the TDEE wizard — read the live
    // presenter value so we never overwrite wizard-set macros with stale text.
    final liveGoals = widget.presenter.goals;

    final goals = NutritionGoals(
      mode: _mode,
      dailyCalories: cal,
      proteinGrams: isStandard
          ? liveGoals.proteinGrams
          : double.tryParse(_proteinCtrl.text.trim()),
      carbsGrams: isStandard
          ? liveGoals.carbsGrams
          : double.tryParse(_carbsCtrl.text.trim()),
      fatGrams: isStandard
          ? liveGoals.fatGrams
          : double.tryParse(_fatCtrl.text.trim()),
      ifSyncEnabled: _ifSync,
      overshootPenaltyEnabled: _overshootPenalty,
    );
    await widget.presenter.updateGoals(goals);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isStandard = _mode == TrackingMode.standard;

    // AppBottomSheet.show owns the chrome (handle, title, close), keyboard inset
    // padding, and the pinned Save action — render only the scrollable form here.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Tracking mode ───────────────────────────────────────
                const _MicroLabel('Tracking mode'),
                const SizedBox(height: 10),
                ...TrackingMode.values.map((m) => AppSelectableTile(
                      mode: AppSelectableMode.radio,
                      selected: _mode == m,
                      onTap: () => setState(() => _mode = m),
                      title: Text(m.label),
                      subtitle: Text(_modeDescription(m)),
                    )),
                const SizedBox(height: 20),

                // ── Simple: manual calorie + optional macro goals ────────
                if (!isStandard) ...[
                  const _MicroLabel('Daily calorie goal'),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: _calCtrl,
                    label: 'kcal / day',
                    hint: 'e.g. 2000',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 14),
                  const _MicroLabel('Macro targets (optional, g)'),
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
                ],

                // ── Standard: TDEE card + fasting lock ──────────────────
                // Macros come from the TDEE wizard — no duplicate field here.
                if (isStandard) ...[
                  // Rebuild when the wizard saves a new profile, so the
                  // target-calories number is fresh on return.
                  ListenableBuilder(
                    listenable: widget.presenter,
                    builder: (_, __) => _TdeeCard(presenter: widget.presenter),
                  ),
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
                  const _MicroLabel('AI Coach'),
                  const SizedBox(height: 10),
                  _AiCoachDownloadCard(presenter: widget.aiCoachPresenter!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Uppercase micro-label used for section headers in the redesigned sheet.
class _MicroLabel extends StatelessWidget {
  final String text;
  const _MicroLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

String _modeDescription(TrackingMode m) {
  switch (m) {
    case TrackingMode.simple:
      return 'Manual calorie + macro goals — quick and minimal';
    case TrackingMode.standard:
      return 'TDEE-based calorie goal · macros from wizard · fasting lock';
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
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MicroLabel('TDEE profile'),
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
              color: context.appColors.gold,
              textAlign: TextAlign.start,
            ),
          if (profile != null) ...[
            const SizedBox(height: 4),
            Text(
              profile.goalLabel.toUpperCase(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          AppSecondaryButton(
            label: profile == null ? 'Set up TDEE' : 'Edit TDEE profile',
            height: 44,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TdeeSetupScreen(presenter: presenter)),
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
    final gold = context.appColors.gold;
    return AppListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: gold,
        activeTrackColor: gold.withValues(alpha: 0.4),
      ),
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
          color: theme.colorScheme.surfaceContainerHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
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
                    AppBadge(
                      text: 'Ready',
                      color: context.appColors.success,
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
