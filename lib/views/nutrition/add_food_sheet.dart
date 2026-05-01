import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/food_entry.dart';
import '../../models/meal_slot.dart';
import '../../presenters/nutrition_presenter.dart';

class AddFoodSheet extends StatefulWidget {
  final NutritionPresenter presenter;

  const AddFoodSheet({super.key, required this.presenter});

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();

  bool _showMacros = false;
  bool _isLogging = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildNameField(),
          const SizedBox(height: 12),
          _buildCaloriesField(),
          const SizedBox(height: 12),
          _buildMacrosToggle(),
          if (_showMacros) ...[
            const SizedBox(height: 12),
            _buildMacrosRow(),
          ],
          const SizedBox(height: 20),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          'LOG FOOD',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 12,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            icon: const Icon(Icons.close,
                color: AppColors.textSecondary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameCtrl,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: _inputDecoration('Food name', 'e.g. Chicken breast 150g'),
    );
  }

  Widget _buildCaloriesField() {
    return TextField(
      controller: _calCtrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: _inputDecoration('Calories', 'kcal'),
    );
  }

  Widget _buildMacrosToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showMacros = !_showMacros),
      child: Row(
        children: [
          Icon(
            _showMacros ? Icons.expand_less : Icons.expand_more,
            color: AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            _showMacros ? 'Hide macros' : 'Add macros (optional)',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacrosRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _proteinCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: _inputDecoration('Protein', 'g'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _carbsCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: _inputDecoration('Carbs', 'g'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _fatCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: _inputDecoration('Fat', 'g'),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(
                    color: AppColors.textSecondary, width: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isLogging ? null : _logFood,
              child: const Text(
                'LOG FOOD',
                style:
                    TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle:
          TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gold, width: 1),
      ),
    );
  }

  Future<void> _logFood() async {
    final name = _nameCtrl.text.trim();
    final calories = int.tryParse(_calCtrl.text.trim());

    if (name.isEmpty || calories == null || calories <= 0) return;

    setState(() => _isLogging = true);

    final entry = FoodEntry(
      id: FoodEntry.generateId(),
      name: name,
      calories: calories,
      protein: double.tryParse(_proteinCtrl.text.trim()),
      carbs: double.tryParse(_carbsCtrl.text.trim()),
      fat: double.tryParse(_fatCtrl.text.trim()),
      loggedAt: DateTime.now(),
    );

    try {
      await widget.presenter.addFoodEntry(entry, MealSlot.snack);
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }
}
