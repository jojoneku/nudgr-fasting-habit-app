import 'package:flutter/material.dart';
import '../../../app_colors.dart';
import '../../../models/hub_card_config.dart';
import '../../../presenters/hub_presenter.dart';
import '../../../utils/app_text_styles.dart';
import '../system/system.dart';

class CustomizeHubSheet extends StatefulWidget {
  final HubPresenter presenter;

  const CustomizeHubSheet({
    super.key,
    required this.presenter,
  });

  @override
  State<CustomizeHubSheet> createState() => _CustomizeHubSheetState();
}

class _CustomizeHubSheetState extends State<CustomizeHubSheet> {
  HubPresenter get presenter => widget.presenter;

  String _cardLabel(HubCardType type) => switch (type) {
        HubCardType.fasting => 'Fasting Timer',
        HubCardType.nutrition => 'Nutrition & Calories',
        HubCardType.activity => 'Daily Activity',
        HubCardType.treasury => 'Treasury & Finance',
        HubCardType.quests => 'Quests & Goals',
        HubCardType.stats => 'Character Stats',
        HubCardType.weightLog => 'Weight & Body',
        HubCardType.bodyMeasurements => 'Body Measurements',
      };

  IconData _cardIcon(HubCardType type) => switch (type) {
        HubCardType.fasting => Icons.timer_outlined,
        HubCardType.nutrition => Icons.restaurant_outlined,
        HubCardType.activity => Icons.directions_run_outlined,
        HubCardType.treasury => Icons.account_balance_outlined,
        HubCardType.quests => Icons.assignment_outlined,
        HubCardType.stats => Icons.person_outlined,
        HubCardType.weightLog => Icons.monitor_weight_outlined,
        HubCardType.bodyMeasurements => Icons.straighten_outlined,
      };

  Color _cardColor(HubCardType type, BuildContext context) {
    final colors = context.appColors;
    return switch (type) {
      HubCardType.fasting => colors.fast,
      HubCardType.nutrition => colors.food,
      HubCardType.activity => colors.move,
      HubCardType.treasury => colors.gold,
      HubCardType.quests => Theme.of(context).colorScheme.secondary,
      HubCardType.stats => Theme.of(context).colorScheme.primary,
      HubCardType.weightLog => colors.purple,
      HubCardType.bodyMeasurements => colors.purple,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        final cards = presenter.allCards;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Customize Hub',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose display density, toggle visibility, and configure smart sorting.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // Smart Sorting Toggle Card
                AppCard(
                  variant: AppCardVariant.elevated,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.appColors.fast.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          color: context.appColors.fast,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Adaptive Sort',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Floats active fasts, urgent quests, and due bills to the top.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: presenter.isSmartSortEnabled,
                        onChanged: presenter.setSmartSortEnabled,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Text(
                  'CARD DENSITY & VISIBILITY',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),

                for (final type in cards) ...[
                  _CardConfigTile(
                    type: type,
                    label: _cardLabel(type),
                    icon: _cardIcon(type),
                    accentColor: _cardColor(type, context),
                    visibility: presenter.visibilityOf(type),
                    isCompact: presenter.isCompact(type),
                    onChanged: (vis) => presenter.setCardVisibility(type, vis),
                  ),
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        presenter.resetToDefaultLayout();
                        AppToast.show(context, 'Reset to default layout');
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reset Layout'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CardConfigTile extends StatelessWidget {
  final HubCardType type;
  final String label;
  final IconData icon;
  final Color accentColor;
  final HubCardVisibility visibility;
  final bool isCompact;
  final ValueChanged<HubCardVisibility> onChanged;

  const _CardConfigTile({
    required this.type,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.visibility,
    required this.isCompact,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: visibility == HubCardVisibility.hidden
                            ? cs.onSurface.withValues(alpha: 0.5)
                            : cs.onSurface,
                      ),
                    ),
                    if (visibility == HubCardVisibility.auto)
                      Text(
                        isCompact ? 'Currently compact' : 'Currently expanded',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<HubCardVisibility>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: HubCardVisibility.auto,
                label: Text('Auto', style: TextStyle(fontSize: 11.5)),
              ),
              ButtonSegment(
                value: HubCardVisibility.expanded,
                label: Text('Expanded', style: TextStyle(fontSize: 11.5)),
              ),
              ButtonSegment(
                value: HubCardVisibility.compact,
                label: Text('Compact', style: TextStyle(fontSize: 11.5)),
              ),
              ButtonSegment(
                value: HubCardVisibility.hidden,
                label: Text('Hidden', style: TextStyle(fontSize: 11.5)),
              ),
            ],
            selected: {visibility},
            onSelectionChanged: (set) {
              if (set.isNotEmpty) onChanged(set.first);
            },
          ),
        ],
      ),
    );
  }
}
