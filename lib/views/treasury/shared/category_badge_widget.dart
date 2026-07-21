import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';

/// The canonical category badge — a rounded-square tonal tile showing either the
/// resolved category icon or, when there's no explicit icon and no keyword
/// match, a name-derived monogram (see [resolveCategoryBadge]). Tinted with the
/// category's [color]. Matches [AppIconBadge]'s look so rows stay consistent.
class CategoryBadge extends StatelessWidget {
  final String? iconKey;
  final String? name;
  final CategoryType type;
  final Color color;
  final double size;
  final double iconSize;

  const CategoryBadge({
    super.key,
    required this.iconKey,
    required this.name,
    required this.type,
    required this.color,
    this.size = 40,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final spec = resolveCategoryBadge(iconKey, name, type);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: spec.monogram != null
          ? Text(
              spec.monogram!,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                // Scale text to the badge; slightly smaller for 2-char monograms.
                fontSize:
                    spec.monogram!.length >= 2 ? size * 0.34 : size * 0.42,
                height: 1,
              ),
            )
          : Icon(spec.icon, color: color, size: iconSize),
    );
  }
}
