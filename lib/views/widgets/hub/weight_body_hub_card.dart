import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_colors.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import '../system/system.dart';

/// Compact 2-up row pairing Weight and Body. The Weight tile reveals an inline
/// single-value quick-entry on tap (Save/Cancel → `logWeight`); the Body tile
/// opens the full multi-field measurement entry (body tracks more than one
/// value, so an inline field can't capture it).
class WeightBodyHubCard extends StatelessWidget {
  const WeightBodyHubCard({
    super.key,
    required this.nutrition,
    required this.onOpenBody,
    this.onOpenWeight,
  });

  final NutritionPresenter nutrition;

  /// Opens the full body-measurement entry screen.
  final VoidCallback onOpenBody;

  /// Optional: open the full weight-log screen (e.g. long-press / header),
  /// distinct from the inline quick-entry.
  final VoidCallback? onOpenWeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: nutrition,
      builder: (context, _) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _WeightTile(
                nutrition: nutrition,
                onOpenFull: onOpenWeight,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _BodyTile(nutrition: nutrition, onOpenFull: onOpenBody),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightTile extends StatefulWidget {
  const _WeightTile({required this.nutrition, this.onOpenFull});
  final NutritionPresenter nutrition;
  final VoidCallback? onOpenFull;

  @override
  State<_WeightTile> createState() => _WeightTileState();
}

class _WeightTileState extends State<_WeightTile> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _beginEdit() {
    final latest = widget.nutrition.latestWeight;
    _ctrl.text = latest != null ? latest.weightKg.toStringAsFixed(1) : '';
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _cancel() {
    setState(() => _editing = false);
    _ctrl.clear();
  }

  Future<void> _save() async {
    final kg = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (kg == null || kg <= 0 || _saving) return;
    setState(() => _saving = true);
    await widget.nutrition.logWeight(kg);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
    });
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: _editing ? null : _beginEdit,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: _editing ? _editor(theme) : _snapshot(theme),
    );
  }

  Widget _snapshot(ThemeData theme) {
    final c = context.appColors;
    final latest = widget.nutrition.latestWeight;
    final delta = widget.nutrition.weightDelta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TileLabel(label: 'WEIGHT', trailing: Icons.edit_outlined),
        const SizedBox(height: 4),
        if (latest == null)
          Text(
            'Tap to add',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else ...[
          Text(
            '${latest.weightKg.toStringAsFixed(1)} kg',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          if (delta != null)
            _DeltaRow(
              down: delta < 0,
              text: '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg',
              color: delta < 0 ? c.move : theme.colorScheme.onSurfaceVariant,
            )
          else
            Text(
              DateFormat('MMM d').format(latest.loggedAt),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ],
    );
  }

  Widget _editor(ThemeData theme) {
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _TileLabel(label: 'LOG WEIGHT'),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: AppTextStyles.bodyMedium,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            isDense: true,
            suffixText: 'kg',
            filled: true,
            fillColor: cs.surfaceContainerHigh,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : _cancel,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

class _BodyTile extends StatelessWidget {
  const _BodyTile({required this.nutrition, required this.onOpenFull});
  final NutritionPresenter nutrition;
  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final latest = nutrition.latestMeasurement;
    final waist = latest?.waistCm;
    final bf = nutrition.estimatedBodyFatPercent;

    return AppCard(
      onTap: onOpenFull,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TileLabel(label: 'BODY', trailing: Icons.chevron_right),
          const SizedBox(height: 4),
          if (latest == null || waist == null)
            Text(
              'Tap to add',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else ...[
            Text(
              nutrition.formatMeasurement(waist),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              bf != null ? '~${bf.toStringAsFixed(0)}% BF' : 'Waist',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: c.fast, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({required this.label, this.trailing});
  final String label;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (trailing != null)
          Icon(trailing, size: 14, color: theme.colorScheme.onSurfaceVariant),
      ],
    );
  }
}

class _DeltaRow extends StatelessWidget {
  const _DeltaRow(
      {required this.down, required this.text, required this.color});
  final bool down;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(down ? Icons.arrow_downward : Icons.arrow_upward,
            size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          text,
          style: AppTextStyles.labelSmall
              .copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
