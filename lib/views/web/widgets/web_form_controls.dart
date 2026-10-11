import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/web_constants.dart';
import 'web_dialog.dart';

/// A `DropdownButtonFormField` in the kit's input style (46 px, radius 12,
/// filled, hairline border), for use inside a [WebField].
///
/// Density is pinned to standard, as [WebInput] does, so the control is the
/// same height as the text inputs beside it. Pass a [key] that changes when
/// the offered [items] change — the form field keeps its own value, and a
/// stale value absent from the new items asserts at build time.
class WebDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool error;
  final bool autofocus;

  const WebDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.error = false,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(visualDensity: VisualDensity.standard),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        autofocus: autofocus,
        isExpanded: true,
        style: WebInput.textStyle(context),
        icon: Icon(
          Icons.expand_more_rounded,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        dropdownColor: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        decoration: WebInput.decoration(context, hint: hint, error: error),
      ),
    );
  }
}

/// A date control in the kit's input style: a calendar icon and the date,
/// "Today, Oct 10" for today, "Oct 3" in the current year, "Oct 3, 2025"
/// otherwise. Tapping opens the shared date picker over [kWebDateRange].
class WebDateButton extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime>? onChanged;

  /// Narrows the pickable range (a payment can't be dated past tomorrow).
  final DateTime? firstDate;
  final DateTime? lastDate;

  const WebDateButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  /// The label the button shows for [date] on [today].
  static String label(DateTime date, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final sameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (sameDay) return 'Today, ${DateFormat('MMM d').format(date)}';
    if (date.year == now.year) return DateFormat('MMM d').format(date);
    return DateFormat('MMM d, yyyy').format(date);
  }

  Future<void> _pick(BuildContext context) async {
    final first = firstDate ?? kWebDateRange.start;
    final last = lastDate ?? kWebDateRange.end;
    final initial = value.isBefore(first)
        ? first
        : value.isAfter(last)
            ? last
            : value;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onChanged != null;
    return Theme(
      data: theme.copyWith(visualDensity: VisualDensity.standard),
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: WebInput.decoration(
            context,
            suffixIcon: Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebInput.textStyle(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line note under a field in the warning tone (short balance, a
/// statement that cannot be paid alone). Informational — it does not block.
class WebFieldWarning extends StatelessWidget {
  final String message;
  final Color color;

  const WebFieldWarning(
      {super.key, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
