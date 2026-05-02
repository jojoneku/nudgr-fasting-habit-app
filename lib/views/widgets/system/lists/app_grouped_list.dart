import 'package:flutter/material.dart';
import '../../../../utils/app_radii.dart';
import '../../../../utils/app_spacing.dart';
import '../../../../utils/app_text_styles.dart';

/// One section within an [AppGroupedList].
class AppGroupedListSection {
  const AppGroupedListSection({
    this.title,
    this.footer,
    required this.children,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;
}

/// HIG inset grouped list — each section is a rounded surface with inset separators.
class AppGroupedList extends StatelessWidget {
  const AppGroupedList({
    super.key,
    required this.sections,
    this.margin = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  });

  final List<AppGroupedListSection> sections;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((section) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.mdGenerous),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.title != null)
                Padding(
                  padding:
                      margin.add(const EdgeInsets.only(bottom: AppSpacing.xs)),
                  child: Text(
                    section.title!,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Container(
                margin: margin,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: AppRadii.lgBorder,
                ),
                child: ClipRRect(
                  borderRadius: AppRadii.lgBorder,
                  child: Column(
                    children: _buildChildren(context, section.children, theme),
                  ),
                ),
              ),
              if (section.footer != null)
                Padding(
                  padding:
                      margin.add(const EdgeInsets.only(top: AppSpacing.xs)),
                  child: Text(
                    section.footer!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _buildChildren(
      BuildContext context, List<Widget> children, ThemeData theme) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(Divider(
          height: 1,
          thickness: 1,
          indent: AppSpacing.md,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ));
      }
    }
    return result;
  }
}
