import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../models/chat_message.dart';
import '../../../models/food_entry.dart';
import '../../../models/food_template.dart';
import '../../../presenters/nutrition_presenter.dart';

/// Reference "Library · save as template" sheet (Nudgr nutrition redesign,
/// `Nutrition Focus More.dc.html`). Shows the template name field, the included
/// items with their calories, and a total, then saves to the food library.
///
/// Returns the saved [FoodTemplate] name on success, or null if cancelled.
/// Theme-aware; no hardcoded per-mode tokens.
Future<String?> showSaveAsTemplateSheet(
  BuildContext context,
  NutritionPresenter presenter,
  ChatMessage message,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _SaveAsTemplateSheet(presenter: presenter, message: message),
  );
}

class _SaveAsTemplateSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  final ChatMessage message;
  const _SaveAsTemplateSheet({required this.presenter, required this.message});

  @override
  State<_SaveAsTemplateSheet> createState() => _SaveAsTemplateSheetState();
}

class _SaveAsTemplateSheetState extends State<_SaveAsTemplateSheet> {
  late final TextEditingController _nameCtrl;
  bool _saving = false;

  String get _suggested {
    final raw = widget.message.rawText.trim();
    return raw.length > 40 ? raw.substring(0, 40) : raw;
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _suggested);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  int get _total => widget.message.foodItems.fold(0, (s, i) => s + i.calories);

  String _gramsLabel(double g) {
    if (g >= 1000) return '${(g / 1000).toStringAsFixed(1)}kg';
    if (g == g.roundToDouble()) return '${g.round()}g';
    return '${g.toStringAsFixed(1)}g';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final items = widget.message.foodItems;
    final name =
        _nameCtrl.text.trim().isEmpty ? _suggested : _nameCtrl.text.trim();
    final template = FoodTemplate(
      id: FoodEntry.generateId(),
      name: name,
      isMeal: items.length > 1,
      entries: items
          .map((item) => FoodEntry(
                id: item.entryId,
                name: item.name,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                grams: item.grams,
                loggedAt: DateTime.now(),
              ))
          .toList(),
    );
    await widget.presenter.saveFoodTemplate(template);
    if (mounted) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = widget.message.foodItems;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottom),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.bookmark_outline,
                  size: 18, color: context.appColors.gold),
              const SizedBox(width: 8),
              Text(
                'Save as template',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('TEMPLATE NAME', cs),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: TextStyle(color: cs.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Template name',
              hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _label('INCLUDES ${items.length} ITEM${items.length == 1 ? '' : 'S'}',
              cs),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: i == items.length - 1
                          ? null
                          : Border(
                              bottom: BorderSide(color: cs.outlineVariant),
                            ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            items[i].grams != null && items[i].grams! > 0
                                ? '${items[i].name} ${_gramsLabel(items[i].grams!)}'
                                : items[i].name,
                            style:
                                TextStyle(color: cs.onSurface, fontSize: 13.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${items[i].calories}',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Total',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$_total ',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'kcal',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                height: 50,
                width: 96,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    side: BorderSide(color: cs.outlineVariant),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.onPrimary),
                          )
                        : const Text('Save to library',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text, ColorScheme cs) => Text(
        text,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      );
}
