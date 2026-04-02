import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../models/meal_slot.dart';
import '../../models/nutrition_goals.dart';
import '../../presenters/nutrition_presenter.dart';
import 'tdee_setup_screen.dart';

/// Bottom sheet: tracking mode, daily calorie goal, macro targets, TDEE wizard link, overshoot penalty.
Future<void> showNutritionSettingsSheet(
    BuildContext context, NutritionPresenter presenter) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NutritionSettingsSheet(presenter: presenter),
  );
}

class _NutritionSettingsSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  const _NutritionSettingsSheet({required this.presenter});

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
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final isStandard = _mode == TrackingMode.standard;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const Text('NUTRITION SETTINGS',
                style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),

            // ── Tracking mode ─────────────────────────────────────────────
            _label('TRACKING MODE'),
            const SizedBox(height: 10),
            ...TrackingMode.values.map((m) => _ModeTile(
                  mode: m,
                  selected: _mode == m,
                  onTap: () => setState(() => _mode = m),
                )),
            const SizedBox(height: 20),

            // ── Simple: manual calorie goal ────────────────────────────────
            if (!isStandard) ...[
              _label('DAILY CALORIE GOAL'),
              const SizedBox(height: 8),
              _numField(_calCtrl, 'kcal / day', 'e.g. 2000'),
              const SizedBox(height: 20),
            ],

            // ── Standard: TDEE + macros + toggles ─────────────────────────
            if (isStandard) ...[
              _TdeeCard(presenter: widget.presenter),
              const SizedBox(height: 20),
              _label('MACRO TARGETS (optional, g)'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _numField(_proteinCtrl, 'Protein', 'g')),
                const SizedBox(width: 10),
                Expanded(child: _numField(_carbsCtrl, 'Carbs', 'g')),
                const SizedBox(width: 10),
                Expanded(child: _numField(_fatCtrl, 'Fat', 'g')),
              ]),
              const SizedBox(height: 20),
              _ToggleRow(
                label: 'Lock logging during fast',
                subtitle: 'Pause food logging while fasting window is active',
                value: _ifSync,
                onChanged: (v) => setState(() => _ifSync = v),
              ),
              const SizedBox(height: 12),
            ],

            // ── Overshoot penalty (both modes) ─────────────────────────────
            _ToggleRow(
              label: 'Overshoot penalty',
              subtitle: '−5 HP when you exceed 120% of goal',
              value: _overshootPenalty,
              onChanged: (v) => setState(() => _overshootPenalty = v),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _save,
                child: const Text('SAVE',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1.8));

  Widget _numField(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.gold, width: 1)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.1)
              : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.5)
                : AppColors.textSecondary.withValues(alpha: 0.2),
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
                Text(mode.label,
                    style: TextStyle(
                        color:
                            selected ? AppColors.gold : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Text(_modeDescription(mode),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TDEE PROFILE',
              style: TextStyle(
                  color: AppColors.gold, fontSize: 10, letterSpacing: 2.0)),
          const SizedBox(height: 8),
          if (profile == null)
            const Text('No profile set — tap below to configure',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
          else
            Text(
              '${profile.targetCalories} kcal/day  ·  ${profile.goal.toUpperCase()}',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
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
                    builder: (_) => TdeeSetupScreen(presenter: presenter)),
              ),
              child: Text(
                profile == null ? 'SET UP TDEE' : 'EDIT TDEE PROFILE',
                style: const TextStyle(fontSize: 12, letterSpacing: 1.4),
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.gold,
          inactiveTrackColor: AppColors.surface,
        ),
      ],
    );
  }
}
