import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intermittent_fasting/utils/app_radii.dart';
import '../../widgets/web_widgets.dart';

/// The editable Allocated cell of the web Budget table, shared by the pre-v2
/// page and `WebBudgetPageV2`.
///
/// Shows the amount with thousands separators while unfocused and the raw
/// digits while editing; focus selects the whole value so typing overwrites
/// it. Commits on Enter and on focus loss, and only calls [onCommit] when the
/// parsed value actually changed, so tabbing through a row does not re-save
/// every cell. Only digits, a dot and a comma are accepted.
///
/// [dashed] is the v2 look from the canvas (`.cell`): a dashed hairline that
/// appears on hover and turns `primary` while focused, telling the eye which
/// column is editable without a permanent input chrome.
class WebBudgetAmountField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onCommit;
  final bool dashed;

  const WebBudgetAmountField({
    super.key,
    required this.value,
    required this.onCommit,
    this.dashed = false,
  });

  @override
  State<WebBudgetAmountField> createState() => _WebBudgetAmountFieldState();
}

class _WebBudgetAmountFieldState extends State<WebBudgetAmountField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _display(widget.value));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant WebBudgetAmountField old) {
    super.didUpdateWidget(old);
    // Keep in sync with the presenter when not actively editing.
    if (!_focus.hasFocus && old.value != widget.value) {
      _controller.text = _display(widget.value);
    }
  }

  String _display(double v) {
    final whole = v.round();
    final s = whole.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      // Show the raw value for editing.
      final v = widget.value;
      _controller.text =
          v == v.roundToDouble() ? v.round().toString() : v.toString();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _commit();
    }
    if (widget.dashed && mounted) setState(() {});
  }

  void _commit() {
    final raw = _controller.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final parsed = double.tryParse(raw) ?? 0;
    _controller.text = _display(parsed);
    if (parsed != widget.value) widget.onCommit(parsed);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      onSubmitted: (_) {
        _commit();
        _focus.unfocus();
      },
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WebInsets.sm,
          vertical: WebInsets.sm,
        ),
        filled: true,
        fillColor: Colors.transparent,
        hoverColor: widget.dashed
            ? Colors.transparent
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadii.smBorder,
          borderSide: BorderSide(color: Colors.transparent),
        ),
        focusedBorder: widget.dashed
            ? const OutlineInputBorder(
                borderRadius: AppRadii.smBorder,
                borderSide: BorderSide(color: Colors.transparent),
              )
            : OutlineInputBorder(
                borderRadius: AppRadii.smBorder,
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
      ),
    );

    if (!widget.dashed) return field;

    // The canvas cell: dashed hairline on hover, primary while editing. Drawn
    // by a painter because InputBorder has no dashed variant.
    final focused = _focus.hasFocus;
    final borderColor = focused
        ? cs.primary
        : _hover
            ? cs.outline
            : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: CustomPaint(
        foregroundPainter: _DashedBorderPainter(
          color: borderColor,
          radius: AppRadii.sm,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (focused || _hover)
                ? cs.surfaceContainerHigh
                : Colors.transparent,
            borderRadius: AppRadii.smBorder,
          ),
          child: field,
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
