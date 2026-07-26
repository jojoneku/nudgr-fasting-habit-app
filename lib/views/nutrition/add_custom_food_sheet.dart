import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_colors.dart'; // context.appColors
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';

/// How the user is entering the numbers.
enum _Basis { perServing, per100g }

/// "Create custom food" form (Phase 1 of the add-a-food feature).
///
/// Lets the user save a food they're confident about into their personal
/// dictionary. Accepts either a **per-serving** entry (e.g. a chocolate bar,
/// 90 kcal per 15 g serving) or a **per-100g** entry (e.g. an own recipe),
/// normalizes to per-100g density, and hands it to
/// [NutritionPresenter.addCustomFood]. From then on the food resolves before
/// the bundled food DB on every log and shows up in typeahead + the Food
/// Library's "My Foods" section.
///
/// Show via [AppBottomSheet.show] with this as the `body`.
class AddCustomFoodSheet extends StatefulWidget {
  final NutritionPresenter presenter;

  const AddCustomFoodSheet({super.key, required this.presenter});

  @override
  State<AddCustomFoodSheet> createState() => _AddCustomFoodSheetState();
}

class _AddCustomFoodSheetState extends State<AddCustomFoodSheet> {
  final _nameCtrl = TextEditingController();
  final _servingCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();

  _Basis _basis = _Basis.perServing;
  bool _showMacros = false;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _servingCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  // ── Derived values ────────────────────────────────────────────────────────

  double? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    return (v != null && v.isFinite) ? v : null;
  }

  /// Scale factor from the entered basis to per-100g.
  ///   per-serving: 100 / servingGrams   (90 kcal / 15 g → ×6.667)
  ///   per-100g:    1
  double? get _scaleToPer100g {
    if (_basis == _Basis.per100g) return 1.0;
    final serving = _parse(_servingCtrl);
    if (serving == null || serving <= 0) return null;
    return 100.0 / serving;
  }

  double? get _kcalPer100g {
    final cal = _parse(_calCtrl);
    final scale = _scaleToPer100g;
    if (cal == null || cal <= 0 || scale == null) return null;
    return cal * scale;
  }

  double? _macroPer100g(TextEditingController c) {
    final v = _parse(c);
    final scale = _scaleToPer100g;
    if (v == null || scale == null) return null;
    return v * scale;
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty && _kcalPer100g != null && !_isSaving;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final kcal = _kcalPer100g;
    if (name.isEmpty) {
      setState(() => _error = 'Give your food a name');
      return;
    }
    if (kcal == null) {
      setState(() => _error = _basis == _Basis.perServing
          ? 'Enter a serving size and calories greater than 0'
          : 'Enter calories greater than 0');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();

    await widget.presenter.addCustomFood(
      name: name,
      kcalPer100g: kcal,
      proteinPer100g: _macroPer100g(_proteinCtrl),
      carbsPer100g: _macroPer100g(_carbsCtrl),
      fatPer100g: _macroPer100g(_fatCtrl),
    );

    if (!mounted) return;
    Navigator.pop(context);
    AppToast.success(context, 'Saved $name to your foods');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _nameCtrl,
          label: 'Food name',
          hint: 'e.g. Dark chocolate bar',
          autofocus: true,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        AppSegmentedControl<_Basis>(
          selected: _basis,
          segments: const [
            (value: _Basis.perServing, label: 'Per serving', icon: null),
            (value: _Basis.per100g, label: 'Per 100g', icon: null),
          ],
          onChanged: (b) => setState(() => _basis = b),
        ),
        const SizedBox(height: 16),
        if (_basis == _Basis.perServing)
          _buildPerServingFields()
        else
          _buildPer100gFields(),
        const SizedBox(height: 12),
        _buildMacrosToggle(cs),
        if (_showMacros) ...[
          const SizedBox(height: 12),
          _buildMacrosRow(cs),
        ],
        const SizedBox(height: 16),
        _buildPreview(cs),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: TextStyle(color: cs.error, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        AppPrimaryButton(
          label: 'Save Food',
          isLoading: _isSaving,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }

  Widget _buildPerServingFields() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppTextField(
            controller: _servingCtrl,
            label: 'Serving size',
            hint: 'grams',
            suffix: const Text('g'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppTextField(
            controller: _calCtrl,
            label: 'Calories',
            hint: 'per serving',
            suffix: const Text('kcal'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildPer100gFields() {
    return AppTextField(
      controller: _calCtrl,
      label: 'Calories per 100g',
      hint: 'kcal',
      suffix: const Text('kcal'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildMacrosToggle(ColorScheme cs) {
    final unit = _basis == _Basis.perServing ? 'per serving' : 'per 100g';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showMacros = !_showMacros),
      child: Row(
        children: [
          Icon(
            _showMacros ? Icons.expand_less : Icons.expand_more,
            color: cs.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            _showMacros ? 'Hide macros' : 'Add macros ($unit, optional)',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMacrosRow(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: AppTextField(
            controller: _proteinCtrl,
            label: 'Protein',
            hint: 'g',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppTextField(
            controller: _carbsCtrl,
            label: 'Carbs',
            hint: 'g',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppTextField(
            controller: _fatCtrl,
            label: 'Fat',
            hint: 'g',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(ColorScheme cs) {
    final kcal = _kcalPer100g;
    final label = kcal == null
        ? 'Stored per 100g once you enter calories'
        : 'Stored as ${kcal.round()} kcal / 100g';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: kcal == null ? cs.onSurfaceVariant : context.appColors.gold,
                fontSize: 12.5,
                fontWeight: kcal == null ? FontWeight.w400 : FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
