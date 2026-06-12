import 'package:flutter/material.dart';
import 'web_card.dart';
import '../design/web_breakpoints.dart';

/// A [WebCard] standardized for charts: fixed chart height, optional legend
/// row beneath, and a consistent empty state — so every fl_chart on the web
/// app shares the same framing and spacing (Plan 050 polish).
class WebChartCard extends StatelessWidget {
  final String title;
  final String? description;
  final Widget chart;
  final Widget? legend;
  final double height;
  final bool isEmpty;
  final String emptyLabel;

  const WebChartCard({
    super.key,
    required this.title,
    this.description,
    required this.chart,
    this.legend,
    this.height = 240,
    this.isEmpty = false,
    this.emptyLabel = 'No data yet',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return WebCard(
      title: title,
      description: description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            child: isEmpty
                ? Center(
                    child: Text(
                      emptyLabel,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                : chart,
          ),
          if (legend != null && !isEmpty) ...[
            const SizedBox(height: WebInsets.lg),
            legend!,
          ],
        ],
      ),
    );
  }
}

/// A small legend swatch + label, used under [WebChartCard].
class WebLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const WebLegendDot({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: WebInsets.sm),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
