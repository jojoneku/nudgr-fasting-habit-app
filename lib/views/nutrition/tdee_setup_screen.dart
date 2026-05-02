import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/meal_slot.dart';
import '../../models/tdee_profile.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';

class TdeeSetupScreen extends StatefulWidget {
  final NutritionPresenter presenter;
  const TdeeSetupScreen({super.key, required this.presenter});

  @override
  State<TdeeSetupScreen> createState() => _TdeeSetupScreenState();
}

class _TdeeSetupScreenState extends State<TdeeSetupScreen> {
  int _step = 0;

  // Step 1
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String _sex = 'male';

  // Step 2
  ActivityLevel _activityLevel = ActivityLevel.sedentary;

  // Step 3
  String _goal = 'maintain';

  @override
  void initState() {
    super.initState();
    final p = widget.presenter.tdeeProfile;
    if (p != null) {
      _weightCtrl.text = p.weightKg.toString();
      _heightCtrl.text = p.heightCm.toString();
      _ageCtrl.text = p.ageYears.toString();
      _sex = p.sex;
      _activityLevel = p.activityLevel;
      _goal = p.goal;
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  TdeeProfile? get _preview {
    final w = double.tryParse(_weightCtrl.text.trim());
    final h = double.tryParse(_heightCtrl.text.trim());
    final a = int.tryParse(_ageCtrl.text.trim());
    if (w == null || h == null || a == null) return null;
    return TdeeProfile(
      weightKg: w,
      heightCm: h,
      ageYears: a,
      sex: _sex,
      activityLevel: _activityLevel,
      goal: _goal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'TDEE Setup · Step ${_step + 1} of 3',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepIndicator(current: _step),
          const SizedBox(height: 32),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _buildStep(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildNavButtons(),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildBodyStats();
      case 1:
        return _buildActivity();
      case 2:
        return _buildGoalStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBodyStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Body stats',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: AppTextField(
                  controller: _weightCtrl,
                  label: 'Weight',
                  suffix: const Text('kg'),
                  keyboardType: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(
              child: AppTextField(
                  controller: _heightCtrl,
                  label: 'Height',
                  suffix: const Text('cm'),
                  keyboardType: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(
              child: AppTextField(
                  controller: _ageCtrl,
                  label: 'Age',
                  suffix: const Text('yrs'),
                  keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 20),
        Text(
          'Sex',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        AppSegmentedControl<String>(
          segments: const [
            (value: 'male', label: 'Male', icon: null),
            (value: 'female', label: 'Female', icon: null),
          ],
          selected: _sex,
          onChanged: (v) => setState(() => _sex = v),
        ),
      ],
    );
  }

  Widget _buildActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activity level',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        ...ActivityLevel.values.map((level) => _RadioTile(
              label: level.label,
              subtitle: _activityDescription(level),
              value: level,
              groupValue: _activityLevel,
              onChanged: (v) => setState(() => _activityLevel = v!),
            )),
      ],
    );
  }

  Widget _buildGoalStep() {
    final profile = _preview;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Goal',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          _RadioTile(
              label: 'Cut — Lose weight',
              subtitle: 'Calorie deficit (–300 kcal)',
              value: 'cut',
              groupValue: _goal,
              onChanged: (v) => setState(() => _goal = v!)),
          _RadioTile(
              label: 'Maintain',
              subtitle: 'Hold current weight',
              value: 'maintain',
              groupValue: _goal,
              onChanged: (v) => setState(() => _goal = v!)),
          _RadioTile(
              label: 'Bulk — Gain muscle',
              subtitle: 'Calorie surplus (+250 kcal)',
              value: 'bulk',
              groupValue: _goal,
              onChanged: (v) => setState(() => _goal = v!)),
          if (profile != null) ...[
            const SizedBox(height: 24),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your target',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  AppNumberDisplay(
                    value: '${profile.targetCalories}',
                    suffix: 'kcal / day',
                    size: AppNumberSize.headline,
                    color: AppColors.gold,
                    textAlign: TextAlign.start,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'BMR ${profile.bmr} · TDEE ${profile.tdee}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Suggested macros',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    _MacroChip(
                        label: 'Protein',
                        value: '${profile.suggestedProteinG}g'),
                    const SizedBox(width: 8),
                    _MacroChip(
                        label: 'Carbs',
                        value: '${profile.suggestedCarbsG}g'),
                    const SizedBox(width: 8),
                    _MacroChip(
                        label: 'Fat', value: '${profile.suggestedFatG}g'),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'These will be applied to your macro targets.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    final isLast = _step == 2;
    return Row(
      children: [
        if (_step > 0) ...[
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => setState(() => _step--),
                child: const Text('Back'),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: AppPrimaryButton(
            label: isLast ? 'Confirm' : 'Next',
            onPressed: isLast ? _confirm : _next,
          ),
        ),
      ],
    );
  }

  bool get _step1Valid {
    return double.tryParse(_weightCtrl.text.trim()) != null &&
        double.tryParse(_heightCtrl.text.trim()) != null &&
        int.tryParse(_ageCtrl.text.trim()) != null;
  }

  void _next() {
    if (_step == 0 && !_step1Valid) return;
    setState(() => _step++);
  }

  Future<void> _confirm() async {
    final profile = _preview;
    if (profile == null) return;
    await widget.presenter.saveTdeeProfile(profile);
    await widget.presenter.updateGoals(
      widget.presenter.goals.copyWith(
        proteinGrams: profile.suggestedProteinG.toDouble(),
        carbsGrams: profile.suggestedCarbsG.toDouble(),
        fatGrams: profile.suggestedFatG.toDouble(),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  String _activityDescription(ActivityLevel level) {
    switch (level) {
      case ActivityLevel.sedentary:
        return 'Little or no exercise';
      case ActivityLevel.lightlyActive:
        return '1–3 days/week';
      case ActivityLevel.moderatelyActive:
        return '3–5 days/week';
      case ActivityLevel.veryActive:
        return '6–7 days/week';
    }
  }
}

// ─── Step Indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int current;
  const _StepIndicator({required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: List.generate(3, (i) {
        final active = i <= current;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
            height: 3,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.gold
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ─── Macro Chip ───────────────────────────────────────────────────────────────

class _MacroChip extends StatelessWidget {
  final String label;
  final String value;
  const _MacroChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Radio Tile ───────────────────────────────────────────────────────────────

class _RadioTile<T> extends StatelessWidget {
  final String label;
  final String? subtitle;
  final T value;
  final T groupValue;
  final void Function(T?) onChanged;
  const _RadioTile({
    required this.label,
    this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Radio<T>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: AppColors.gold,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? AppColors.gold
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
