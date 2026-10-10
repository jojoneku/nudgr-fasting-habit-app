/// The one dialog language for the Treasury web (Plan 063, Phase 2).
///
/// Every v2 form is a [WebDialog] whose body is a column of [WebField]s
/// wrapping [WebInput]s (or dropdowns styled with [WebInput.decoration]),
/// with optional fields tucked into a [WebMoreOptions] fold and conditional
/// sections in a [WebFold]. Confirmations go through [showWebConfirm]. The
/// three pre-v2 form styles (AlertDialog with floating labels, the mobile
/// sheet look, the batch dialog) are all replaced by this file.
///
/// Theme-aware only: colors come from `Theme.of(context)` and
/// `context.appColors`, so each piece renders in dark and light.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_colors.dart';
import '../../../utils/app_radii.dart';
import '../design/web_breakpoints.dart';
import '../design/web_constants.dart';
import '../design/web_theme.dart';
import 'web_number.dart';

/// Opens [builder]'s widget as a modal dialog. The same as [showDialog] with
/// the kit's defaults named in one place; Esc and the barrier close it unless
/// [barrierDismissible] is false.
Future<T?> showWebDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

/// A 520 px dialog on the card surface with a header (title, optional
/// subtitle, close ×), a scrollable body and a [WebDialogFooter].
///
/// Footer rules, from the canvas: a [destructive] action sits at the far left;
/// the ghost [secondary] and filled [primary] sit at the right. With no
/// destructive action the primary expands to fill the row (the "Add bill"
/// shape) unless [primaryExpands] is false (the confirm shape, where the
/// primary stays a compact button at the right).
class WebDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget primary;
  final Widget? secondary;
  final Widget? destructive;
  final double width;
  final bool showClose;
  final bool primaryExpands;

  const WebDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    required this.primary,
    this.secondary,
    this.destructive,
    this.width = kWebDialogWidth,
    this.showClose = true,
    this.primaryExpands = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      backgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kWebDialogRadius),
        side: BorderSide(color: cs.outline),
      ),
      insetPadding: const EdgeInsets.all(WebInsets.xl),
      clipBehavior: Clip.antiAlias,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WebDialogHeader(
                  title: title,
                  subtitle: subtitle,
                  showClose: showClose,
                ),
                const SizedBox(height: WebInsets.lg),
                Flexible(
                  child: SingleChildScrollView(child: body),
                ),
                const SizedBox(height: WebInsets.lg),
                WebDialogFooter(
                  primary: primary,
                  secondary: secondary,
                  destructive: destructive,
                  primaryExpands: primaryExpands,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebDialogHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showClose;

  const _WebDialogHeader({
    required this.title,
    required this.subtitle,
    required this.showClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.17,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showClose) ...[
          const SizedBox(width: WebInsets.md),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, size: 18),
            style: IconButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              hoverColor: cs.surfaceContainerHigh,
              minimumSize: const Size(kWebHitTarget, kWebHitTarget),
              maximumSize: const Size(kWebHitTarget, kWebHitTarget),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The footer row of a [WebDialog]. Exposed so a page that renders a form
/// inline (not in a dialog) can keep the same button rules.
class WebDialogFooter extends StatelessWidget {
  final Widget primary;
  final Widget? secondary;
  final Widget? destructive;
  final bool primaryExpands;

  const WebDialogFooter({
    super.key,
    required this.primary,
    this.secondary,
    this.destructive,
    this.primaryExpands = true,
  });

  Widget _tall(Widget w) => SizedBox(height: kWebDialogButtonHeight, child: w);

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: WebInsets.sm);
    final List<Widget> children;
    if (destructive != null) {
      children = [
        _tall(destructive!),
        const Spacer(),
        if (secondary != null) ...[_tall(secondary!), gap],
        _tall(primary),
      ];
    } else if (primaryExpands) {
      children = [
        if (secondary != null) ...[_tall(secondary!), gap],
        Expanded(child: _tall(primary)),
      ];
    } else {
      children = [
        if (secondary != null) _tall(secondary!),
        const Spacer(),
        _tall(primary),
      ];
    }
    return Padding(
      padding: const EdgeInsets.only(top: WebInsets.xs),
      child: Row(children: children),
    );
  }
}

/// An uppercase 10.5/700 label above a control, with an optional muted
/// "optional" suffix, and a helper or error line under it.
///
/// The control itself is the [child] — a [WebInput], a dropdown using
/// [WebInput.decoration], a date button. The error text is rendered here (in
/// `colorScheme.error`); pass `error: true` to the [WebInput] as well so its
/// border turns red.
class WebField extends StatelessWidget {
  final String label;
  final bool optional;
  final String? helper;
  final String? error;
  final Widget child;

  const WebField({
    super.key,
    required this.label,
    this.optional = false,
    this.helper,
    this.error,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;
    final note = error ?? helper;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  // .07em at 10.5 px.
                  letterSpacing: 0.74,
                ),
              ),
            ),
            if (optional) ...[
              const SizedBox(width: 6),
              Text(
                'optional',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: note == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: error != null ? cs.error : muted,
                      fontSize: 12,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

enum _WebInputKind { text, amount, multiline }

/// A [TextField] in the canvas input style: 46 px tall, radius 12, filled
/// `surfaceContainerHigh`, hairline `outlineVariant` border, a 1.5 px
/// `primary` focus ring and an `error` border when [error] is set.
///
/// [WebInput.amount] is the 64 px, 28/800 tabular-numeral money input with a
/// `₱` prefix; [WebInput.multiline] grows from three lines for notes.
///
/// The decoration is also available on its own as [WebInput.decoration] so a
/// `DropdownButtonFormField` or an `InputDecorator` (date buttons) can match.
class WebInput extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final String? prefixText;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;

  /// Turns the border red. The message itself belongs to the enclosing
  /// [WebField.error].
  final bool error;
  final TextAlign textAlign;
  final int? maxLength;
  final int? minLines;
  final int? maxLines;
  final _WebInputKind _kind;

  const WebInput({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.prefixText,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.error = false,
    this.textAlign = TextAlign.start,
    this.maxLength,
  })  : _kind = _WebInputKind.text,
        minLines = null,
        maxLines = 1;

  /// The large money input: 64 px, 28/800, tabular numerals, `₱` prefix.
  const WebInput.amount({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = '0.00',
    this.prefixText = '₱',
    this.suffix,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.error = false,
  })  : _kind = _WebInputKind.amount,
        prefix = null,
        keyboardType = const TextInputType.numberWithOptions(decimal: true),
        textAlign = TextAlign.start,
        maxLength = null,
        minLines = null,
        maxLines = 1;

  /// A notes input that grows from [minLines] to [maxLines].
  const WebInput.multiline({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.error = false,
    this.maxLength,
    this.minLines = 3,
    this.maxLines = 6,
  })  : _kind = _WebInputKind.multiline,
        prefixText = null,
        prefix = null,
        suffix = null,
        keyboardType = TextInputType.multiline,
        inputFormatters = null,
        onTap = null,
        textAlign = TextAlign.start;

  /// Text style of a standard input. Line height is fixed so the field is
  /// exactly [kWebInputHeight] tall with [decoration]'s padding.
  static TextStyle textStyle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: 14,
      height: 1.5, // 21 px line
    );
  }

  /// Text style of the amount input (28/800, tabular, −0.02em).
  static TextStyle amountStyle(BuildContext context) {
    final theme = Theme.of(context);
    return webNumericStyle(
          (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.56,
            height: 1.25, // 35 px line
          ),
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle();
  }

  /// The canvas input decoration, for a [TextField] or any other
  /// `InputDecorator` host (dropdowns, date buttons).
  ///
  /// [height] fixes the control's height through its content padding
  /// (defaults to [kWebInputHeight]; pass `null` for a growing multiline
  /// field). Hosts other than [WebInput] should render inside a `Theme` with
  /// `visualDensity: VisualDensity.standard`, as [WebInput] does, or the
  /// desktop "compact" density shaves 8 px off the result.
  static InputDecoration decoration(
    BuildContext context, {
    String? hint,
    String? prefixText,
    Widget? prefix,
    Widget? suffix,
    Widget? suffixIcon,
    bool error = false,
    bool large = false,
    double? height = kWebInputHeight,
    double lineHeight = 21,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;
    OutlineInputBorder box(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: AppRadii.mdBorder,
          borderSide: BorderSide(color: c, width: w),
        );
    final idle = cs.outlineVariant.withValues(alpha: 0.6);
    final double vertical =
        height == null ? 12.5 : ((height - lineHeight) / 2).clamp(0.0, 999.0);

    return InputDecoration(
      hintText: hint,
      hintStyle: (large ? amountStyle(context) : textStyle(context))
          .copyWith(color: muted, fontWeight: large ? FontWeight.w700 : null),
      prefixText: prefixText == null ? null : '$prefixText ',
      prefixStyle: large
          ? amountStyle(context).copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: muted,
            )
          : textStyle(context).copyWith(fontSize: 13, color: muted),
      prefix: prefix,
      suffix: suffix,
      suffixIcon: suffixIcon,
      suffixIconColor: muted,
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      isDense: true,
      counterText: '',
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: vertical),
      enabledBorder: box(error ? cs.error : idle),
      border: box(idle),
      focusedBorder: box(error ? cs.error : cs.primary, 1.5),
      errorBorder: box(cs.error),
      focusedErrorBorder: box(cs.error, 1.5),
      disabledBorder: box(cs.outlineVariant.withValues(alpha: 0.3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final large = _kind == _WebInputKind.amount;
    final style = large ? amountStyle(context) : textStyle(context);

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textAlign: textAlign,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      style: style,
      cursorColor: theme.colorScheme.primary,
      decoration: decoration(
        context,
        hint: hint,
        prefixText: prefixText,
        prefix: prefix,
        suffix: suffix,
        error: error,
        large: large,
        height: switch (_kind) {
          _WebInputKind.text => kWebInputHeight,
          _WebInputKind.amount => kWebAmountInputHeight,
          _WebInputKind.multiline => null,
        },
        lineHeight: large ? 35 : 21,
      ),
    );

    // Pin the density: the input's height is computed from its padding, and
    // the adaptive desktop density would otherwise subtract from it.
    return Theme(
      data: theme.copyWith(visualDensity: VisualDensity.standard),
      child: field,
    );
  }
}

/// A titled fold — a bordered section with a header and a body that shows or
/// hides. Two modes:
///
/// * **Switch** — pass [toggle] and [onToggle]: the header carries a switch,
///   the body is visible while the switch is on ("Split into installments").
/// * **Disclosure** — leave [toggle] null: the header is a tappable row with a
///   chevron and the fold opens/closes on its own ([initiallyOpen] seeds it).
class WebFold extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool? toggle;
  final ValueChanged<bool>? onToggle;
  final bool initiallyOpen;
  final Widget child;

  const WebFold({
    super.key,
    required this.title,
    this.subtitle,
    this.toggle,
    this.onToggle,
    this.initiallyOpen = false,
    required this.child,
  });

  @override
  State<WebFold> createState() => _WebFoldState();
}

class _WebFoldState extends State<WebFold> {
  late bool _open = widget.toggle ?? widget.initiallyOpen;

  @override
  void didUpdateWidget(covariant WebFold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.toggle != null && widget.toggle != oldWidget.toggle) {
      _open = widget.toggle!;
    }
  }

  void _flip() {
    if (widget.toggle != null) {
      widget.onToggle?.call(!widget.toggle!);
    } else {
      setState(() => _open = !_open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final controlled = widget.toggle != null;

    final header = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: WebInsets.sm),
        if (controlled)
          Switch(
            value: widget.toggle!,
            onChanged: widget.onToggle,
          )
        else
          AnimatedRotation(
            turns: _open ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.55),
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _flip,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kWebHitTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: WebInsets.sm,
                ),
                child: header,
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The "▸ More options" disclosure under a form's required fields. Closed by
/// default; [children] stack with a 14 px gap once opened. [hint] names what
/// is inside ("notes, I'll get this back") so the user knows before opening.
class WebMoreOptions extends StatefulWidget {
  final List<Widget> children;
  final String label;
  final String? hint;
  final bool initiallyOpen;

  const WebMoreOptions({
    super.key,
    required this.children,
    this.label = 'More options',
    this.hint,
    this.initiallyOpen = false,
  });

  @override
  State<WebMoreOptions> createState() => _WebMoreOptionsState();
}

class _WebMoreOptionsState extends State<WebMoreOptions> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(
              foregroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(horizontal: WebInsets.xs),
              minimumSize: const Size(0, kWebButtonMinHeight),
              alignment: Alignment.centerLeft,
            ),
            icon: AnimatedRotation(
              turns: _open ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: const Icon(Icons.chevron_right_rounded, size: 18),
            ),
            label: Text.rich(
              TextSpan(
                text: widget.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  if (widget.hint != null)
                    TextSpan(
                      text: ' · ${widget.hint}',
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: WebInsets.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.children.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        widget.children[i],
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Tone of a selected [WebSegment]: the Expense/Income/Transfer control tints
/// its active segment by what the choice means.
enum WebSegmentTone { neutral, warning, success }

/// One option of a [WebSegmented].
class WebSegment<T> {
  final T value;
  final String label;
  final WebSegmentTone tone;
  final IconData? icon;

  const WebSegment(
    this.value,
    this.label, {
    this.tone = WebSegmentTone.neutral,
    this.icon,
  });
}

/// A segmented control with equal-width segments and a per-segment tone on
/// the active one (warning for outflow, success for inflow, neutral for a
/// transfer or an "All" filter).
class WebSegmented<T> extends StatelessWidget {
  final List<WebSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  const WebSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = context.appColors.bills;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border.all(color: cs.outline),
        borderRadius: AppRadii.mdBorder,
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: _Segment<T>(
                segment: segments[i],
                selected: segments[i].value == value,
                warning: warning,
                onTap: () => onChanged(segments[i].value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  final WebSegment<T> segment;
  final bool selected;
  final Color warning;
  final VoidCallback onTap;

  const _Segment({
    required this.segment,
    required this.selected,
    required this.warning,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (Color bg, Color fg) = !selected
        ? (Colors.transparent, cs.onSurfaceVariant)
        : switch (segment.tone) {
            WebSegmentTone.neutral => (cs.surfaceContainerHigh, cs.onSurface),
            WebSegmentTone.warning => (
                warning.withValues(alpha: 0.16),
                warning
              ),
            WebSegmentTone.success => (
                cs.tertiary.withValues(alpha: 0.16),
                cs.tertiary
              ),
          };
    final radius = BorderRadius.circular(9);
    return Semantics(
      button: true,
      selected: selected,
      label: segment.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (segment.icon != null) ...[
                Icon(segment.icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  segment.label,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One pill of a [WebChips] row.
class WebChipOption<T> {
  final T value;
  final String label;

  const WebChipOption(this.value, this.label);
}

/// A wrapping row of pill chips with one selected value (installment months,
/// interest presets, reminder days).
///
/// With [allowCustom], a trailing [customLabel] chip calls [onCustom]; it
/// renders selected whenever [value] is not one of the [options], so a value
/// typed by hand still shows where it came from.
class WebChips<T> extends StatelessWidget {
  final List<WebChipOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final bool allowCustom;
  final String customLabel;
  final VoidCallback? onCustom;

  const WebChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.allowCustom = false,
    this.customLabel = 'Custom…',
    this.onCustom,
  });

  bool get _customSelected =>
      allowCustom && value != null && !options.any((o) => o.value == value);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 0,
      children: [
        for (final o in options)
          _Chip(
            label: o.label,
            selected: o.value == value,
            onTap: () => onChanged(o.value),
          ),
        if (allowCustom)
          _Chip(
            label: customLabel,
            selected: _customSelected,
            onTap: onCustom,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shape = StadiumBorder(
      side: BorderSide(color: selected ? cs.primary : cs.outline),
    );
    // 4 px of transparent hit padding above and below brings the 32 px pill
    // to the 40 px web pointer target without widening the visual gap.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? cs.primary.withValues(alpha: 0.14)
              : cs.surfaceContainerLow,
          shape: shape,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(
                label,
                softWrap: false,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bordered row with a title, a one-line explanation and a switch at the
/// right ("I'll get this back", "Repeats monthly"). The whole row toggles.
class WebSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const WebSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onChanged != null;
    return Material(
      color: theme.scaffoldBackgroundColor.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.mdBorder,
        side: BorderSide(color: cs.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kWebHitTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WebInsets.md,
              vertical: 6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          fontSize: 13.5,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: WebInsets.sm),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one confirm style: a [WebDialog] with the message as its body, a ghost
/// Cancel at the left and a filled confirm at the right — red when
/// [destructive]. Resolves to true only when the confirm button is pressed;
/// Cancel, ×, Esc and the barrier all resolve to false.
Future<bool> showWebConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showWebDialog<bool>(
    context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      return WebDialog(
        title: title,
        primaryExpands: false,
        body: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        secondary: TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        primary: FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      );
    },
  );
  return result ?? false;
}
