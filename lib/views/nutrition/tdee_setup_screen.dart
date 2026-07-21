import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/meal_slot.dart';
import '../../models/tdee_profile.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';
import 'widgets/tdee_step_forms.dart';

class TdeeSetupScreen extends StatefulWidget {
  final NutritionPresenter presenter;
  const TdeeSetupScreen({super.key, required this.presenter});

  @override
  State<TdeeSetupScreen> createState() => _TdeeSetupScreenState();
}

class _TdeeSetupScreenState extends State<TdeeSetupScreen> {
  int _step = 0;

  // Step 1 — body stats
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String _sex = 'male';

  // Step 2 — activity
  ActivityLevel _activityLevel = ActivityLevel.sedentary;

  // Step 3 — goal + calorie adjustment
  String _goal = 'maintain';
  // null = custom input; int = a selected preset or 0 for maintain
  int? _selectedAdjustment = 0;
  final _customAdjCtrl = TextEditingController();

  // Step 4 — editable macro targets (pre-filled from TDEE suggestions)
  final _reviewProteinCtrl = TextEditingController();
  final _reviewCarbsCtrl = TextEditingController();
  final _reviewFatCtrl = TextEditingController();

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
      _initAdjustment(p.goal, p.calorieAdjustment);
    }
  }

  void _initAdjustment(String goal, int? savedAdj) {
    const cutPresets = {-200, -300, -500};
    const bulkPresets = {150, 250};
    if (savedAdj == null) {
      // Legacy profile — map goal to default preset
      _selectedAdjustment = switch (goal) {
        'cut' => -300,
        'bulk' => 250,
        _ => 0,
      };
      return;
    }
    if (goal == 'maintain' || savedAdj == 0) {
      _selectedAdjustment = 0;
    } else if (goal == 'cut' && cutPresets.contains(savedAdj)) {
      _selectedAdjustment = savedAdj;
    } else if (goal == 'bulk' && bulkPresets.contains(savedAdj)) {
      _selectedAdjustment = savedAdj;
    } else {
      _selectedAdjustment = null; // custom
      _customAdjCtrl.text = savedAdj.abs().toString();
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    _customAdjCtrl.dispose();
    _reviewProteinCtrl.dispose();
    _reviewCarbsCtrl.dispose();
    _reviewFatCtrl.dispose();
    super.dispose();
  }

  void _onGoalChanged(String goal) {
    setState(() {
      _goal = goal;
      _customAdjCtrl.clear();
      _selectedAdjustment = switch (goal) {
        'cut' => -300,
        'bulk' => 250,
        _ => 0,
      };
    });
  }

  TdeeProfile? get _preview {
    final w = double.tryParse(_weightCtrl.text.trim());
    final h = double.tryParse(_heightCtrl.text.trim());
    final a = int.tryParse(_ageCtrl.text.trim());
    if (w == null || h == null || a == null) return null;

    int adj;
    if (_goal == 'maintain') {
      adj = 0;
    } else if (_selectedAdjustment != null) {
      adj = _selectedAdjustment!;
    } else {
      final customVal = int.tryParse(_customAdjCtrl.text.trim());
      if (customVal == null || customVal <= 0) return null;
      adj = _goal == 'cut' ? -customVal : customVal;
    }

    return TdeeProfile(
      weightKg: w,
      heightCm: h,
      ageYears: a,
      sex: _sex,
      activityLevel: _activityLevel,
      goal: _goal,
      calorieAdjustment: adj,
    );
  }

  bool get _step1Valid =>
      double.tryParse(_weightCtrl.text.trim()) != null &&
      double.tryParse(_heightCtrl.text.trim()) != null &&
      int.tryParse(_ageCtrl.text.trim()) != null;

  bool get _step2Valid {
    if (_goal == 'maintain') return true;
    if (_selectedAdjustment != null) return true;
    final val = int.tryParse(_customAdjCtrl.text.trim());
    return val != null && val > 0;
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'TDEE Setup · Step ${_step + 1} of 4',
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StepIndicator(current: _step),
            const SizedBox(height: 32),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _buildStep(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildNavButtons(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      0 => _buildBodyStats(),
      1 => _buildActivity(),
      2 => _buildGoalStep(),
      3 => _buildReviewStep(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildBodyStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TdeeHeading('About you', 'The basics behind your calorie math.'),
        BodyStatsForm(
          weightCtrl: _weightCtrl,
          heightCtrl: _heightCtrl,
          ageCtrl: _ageCtrl,
          sex: _sex,
          onSexChanged: (v) => setState(() => _sex = v),
        ),
      ],
    );
  }

  Widget _buildActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TdeeHeading('Activity level', 'How active is a typical week?'),
        ActivityLevelSelector(
          selected: _activityLevel,
          onChanged: (v) => setState(() => _activityLevel = v),
        ),
      ],
    );
  }

  Widget _buildGoalStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TdeeHeading("Your goal", "We'll size your targets around it."),
          TdeeSelectCard(
            icon: Icons.trending_down,
            title: 'Cut',
            subtitle: 'Lose fat · calorie deficit',
            selected: _goal == 'cut',
            onTap: () => _onGoalChanged('cut'),
          ),
          if (_goal == 'cut') _buildAdjPicker(isCut: true),
          TdeeSelectCard(
            icon: Icons.drag_handle,
            title: 'Maintain',
            subtitle: 'Hold weight · at TDEE',
            selected: _goal == 'maintain',
            onTap: () => _onGoalChanged('maintain'),
          ),
          TdeeSelectCard(
            icon: Icons.trending_up,
            title: 'Lean gain',
            subtitle: 'Build muscle · calorie surplus',
            selected: _goal == 'bulk',
            onTap: () => _onGoalChanged('bulk'),
          ),
          if (_goal == 'bulk') _buildAdjPicker(isCut: false),
        ],
      ),
    );
  }

  Widget _buildAdjPicker({required bool isCut}) {
    final theme = Theme.of(context);
    final isCustom = _selectedAdjustment == null;

    final List<({int value, String label, String desc})> options = isCut
        ? [
            (value: -200, label: '−200 kcal', desc: 'Mild'),
            (value: -300, label: '−300 kcal', desc: 'Moderate'),
            (value: -500, label: '−500 kcal', desc: 'Aggressive'),
          ]
        : [
            (value: 150, label: '+150 kcal', desc: 'Lean'),
            (value: 250, label: '+250 kcal', desc: 'Standard'),
          ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isCut ? 'Daily deficit' : 'Daily surplus',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final opt in options) ...[
                Expanded(
                  child: _AdjChip(
                    topLabel: opt.desc,
                    bottomLabel: opt.label,
                    selected: _selectedAdjustment == opt.value,
                    onTap: () => setState(() {
                      _selectedAdjustment = opt.value;
                      _customAdjCtrl.clear();
                    }),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: _AdjChip(
                  topLabel: 'Custom',
                  bottomLabel: isCut ? 'deficit' : 'surplus',
                  selected: isCustom,
                  onTap: () => setState(() => _selectedAdjustment = null),
                ),
              ),
            ],
          ),
          if (isCustom) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 180,
              child: AppTextField(
                controller: _customAdjCtrl,
                label: isCut ? 'Deficit (kcal/day)' : 'Surplus (kcal/day)',
                hint: isCut ? 'e.g. 350' : 'e.g. 200',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final profile = _preview;
    final theme = Theme.of(context);

    if (profile == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Please complete all previous steps.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final goalLabel = switch (_goal) {
      'cut' => 'Cut',
      'bulk' => 'Lean gain',
      _ => 'Maintain',
    };
    final delta = profile.targetCalories - profile.tdee;
    final goalLine = delta == 0
        ? goalLabel
        : '$goalLabel · ${delta > 0 ? '+' : '−'}${delta.abs()} kcal';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TdeeHeading(
              'Your targets', 'Fine-tune your macros if you like.'),
          AppCard(
            child: Column(
              children: [
                Text(
                  'DAILY TARGET',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                TdeeCountUp(
                  value: profile.targetCalories,
                  suffix: ' kcal',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  goalLine,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: context.appColors.fast,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TdeeStatTile(label: 'BMR', value: '${profile.bmr}')),
            const SizedBox(width: 8),
            Expanded(
                child: TdeeStatTile(label: 'TDEE', value: '${profile.tdee}')),
          ]),
          const SizedBox(height: 16),
          Text(
            'MACRO TARGETS (G)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: AppTextField(
                controller: _reviewProteinCtrl,
                label: 'Protein',
                hint: 'g',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppTextField(
                controller: _reviewCarbsCtrl,
                label: 'Carbs',
                hint: 'g',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppTextField(
                controller: _reviewFatCtrl,
                label: 'Fat',
                hint: 'g',
                keyboardType: TextInputType.number,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Pre-filled from TDEE — adjust if needed.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    final isLast = _step == 3;
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

  void _next() {
    if (_step == 0 && !_step1Valid) return;
    if (_step == 2 && !_step2Valid) return;
    if (_step == 2) {
      final profile = _preview;
      if (profile != null) {
        _reviewProteinCtrl.text = '${profile.suggestedProteinG}';
        _reviewCarbsCtrl.text = '${profile.suggestedCarbsG}';
        _reviewFatCtrl.text = '${profile.suggestedFatG}';
      }
    }
    setState(() => _step++);
  }

  Future<void> _confirm() async {
    final profile = _preview;
    if (profile == null) return;
    await widget.presenter.saveTdeeProfile(profile);
    final protein = double.tryParse(_reviewProteinCtrl.text.trim()) ??
        profile.suggestedProteinG.toDouble();
    final carbs = double.tryParse(_reviewCarbsCtrl.text.trim()) ??
        profile.suggestedCarbsG.toDouble();
    final fat = double.tryParse(_reviewFatCtrl.text.trim()) ??
        profile.suggestedFatG.toDouble();
    await widget.presenter.updateGoals(
      widget.presenter.goals.copyWith(
        proteinGrams: protein,
        carbsGrams: carbs,
        fatGrams: fat,
      ),
    );
    if (mounted) Navigator.pop(context);
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
      children: List.generate(4, (i) {
        final active = i <= current;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
            height: 3,
            decoration: BoxDecoration(
              color: active
                  ? context.appColors.fast
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ─── Adjustment Chip ─────────────────────────────────────────────────────────

class _AdjChip extends StatelessWidget {
  final String topLabel;
  final String bottomLabel;
  final bool selected;
  final VoidCallback onTap;
  const _AdjChip({
    required this.topLabel,
    required this.bottomLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gold = context.appColors.gold;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? gold.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? gold.withValues(alpha: 0.6)
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              topLabel,
              style: TextStyle(
                color: selected ? gold : theme.colorScheme.onSurface,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            Text(
              bottomLabel,
              style: TextStyle(
                color: selected
                    ? gold.withValues(alpha: 0.8)
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
