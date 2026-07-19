import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_colors.dart';
import '../../../models/chat_message.dart';
import '../../../models/estimation_source.dart';
import '../../../models/food_db_entry.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../widgets/system/system.dart';
import 'save_as_template_sheet.dart';

/// "Today's log" list for the redesigned Nutrition screen (Nudgr redesign).
///
/// Renders the presenter's [NutritionPresenter.logEntriesNewestFirst] as a flat
/// newest-first stack of structured entry cards (no meal-slot grouping), with a
/// header showing the day's total kcal. Each entry is one logged food/meal or
/// exercise. All colours read from the theme; Material icons only.
class NutritionLogList extends StatelessWidget {
  final NutritionPresenter presenter;
  const NutritionLogList({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = presenter.logEntriesNewestFirst;

    if (entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.chat_bubble_outline,
        title: presenter.isSelectedDateToday
            ? 'Log food or exercise below'
            : 'Nothing logged',
        iconSize: 40,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 11),
            child: Row(
              children: [
                Text(
                  "Today's log",
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${NumberFormat.decimalPattern().format(presenter.todayCalories)} kcal',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }
        final entryIndex = index - 1;
        final message = entries[entryIndex];
        // Subtle accent emphasis on the freshly-logged top entry today — fades
        // out on the next rebuild once the entry is a few seconds old.
        final highlight = entryIndex == 0 &&
            presenter.isSelectedDateToday &&
            DateTime.now().difference(message.timestamp).inSeconds < 8;
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: _LogEntryCard(
            key: ValueKey(message.id),
            message: message,
            presenter: presenter,
            highlight: highlight,
          ),
        );
      },
    );
  }
}

// ─── Entry card dispatcher ──────────────────────────────────────────────────

class _LogEntryCard extends StatelessWidget {
  final ChatMessage message;
  final NutritionPresenter presenter;
  final bool highlight;
  const _LogEntryCard({
    super.key,
    required this.message,
    required this.presenter,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    if (message.kind == ChatMessageKind.exercise) {
      if (message.exerciseEntry == null) return const SizedBox.shrink();
      return _ExerciseEntryCard(message: message, presenter: presenter);
    }
    return _FoodEntryCard(
      message: message,
      presenter: presenter,
      highlight: highlight,
    );
  }
}

// ─── Card shell ─────────────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  final bool highlight;
  final Widget child;
  const _CardShell({required this.highlight, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? cs.primary.withValues(alpha: 0.45)
              : cs.outlineVariant,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.10),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      child: child,
    );
  }
}

// ─── Food entry card ────────────────────────────────────────────────────────

class _FoodEntryCard extends StatefulWidget {
  final ChatMessage message;
  final NutritionPresenter presenter;
  final bool highlight;
  const _FoodEntryCard({
    required this.message,
    required this.presenter,
    required this.highlight,
  });

  @override
  State<_FoodEntryCard> createState() => _FoodEntryCardState();
}

class _FoodEntryCardState extends State<_FoodEntryCard> {
  bool _menuOpen = false;
  bool _editing = false;
  bool _saving = false;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _resetControllers();
  }

  void _resetControllers() {
    _controllers = widget.message.foodItems
        .map(
            (item) => TextEditingController(text: item.amountText ?? item.name))
        .toList();
  }

  @override
  void didUpdateWidget(_FoodEntryCard old) {
    super.didUpdateWidget(old);
    if (!_editing) {
      for (final c in _controllers) {
        c.dispose();
      }
      _resetControllers();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final texts = _controllers.map((c) => c.text.trim()).toList();
    await widget.presenter.editAllChatFoodItems(widget.message.id, texts);
    if (mounted) {
      setState(() {
        _editing = false;
        _saving = false;
      });
    }
  }

  void _cancel() {
    setState(() {
      _editing = false;
      for (var i = 0; i < _controllers.length; i++) {
        final item = widget.message.foodItems[i];
        _controllers[i].text = item.amountText ?? item.name;
      }
    });
  }

  Future<void> _onDislike() async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.presenter.markChatMessageDisliked(widget.message.id);
    if (!mounted) return;
    setState(() => _menuOpen = false);
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Thanks — we'll improve the match next time."),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onDelete() async {
    final messenger = ScaffoldMessenger.of(context);
    final msg = widget.message;
    final name = msg.rawText;
    await widget.presenter.removeChatMessage(msg.id);
    if (!mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed · $name'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.presenter.restoreChatMessage(msg),
          ),
        ),
      );
  }

  Future<void> _saveAsTemplate() async {
    final messenger = ScaffoldMessenger.of(context);
    final savedName = await showSaveAsTemplateSheet(
      context,
      widget.presenter,
      widget.message,
    );
    if (savedName == null || !mounted) return;
    setState(() => _menuOpen = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved "$savedName" to library'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      highlight: widget.highlight,
      child: _editing ? _buildEditing(context) : _buildCollapsed(context),
    );
  }

  // ── Collapsed (reference) summary ─────────────────────────────────────────
  Widget _buildCollapsed(BuildContext context) {
    final message = widget.message;
    final cs = Theme.of(context).colorScheme;
    final items = message.foodItems;

    var kcal = 0;
    double p = 0, c = 0, f = 0;
    for (final item in items) {
      kcal += item.calories;
      p += item.protein ?? 0;
      c += item.carbs ?? 0;
      f += item.fat ?? 0;
    }

    final name = message.rawText.trim().isNotEmpty
        ? message.rawText
        : (items.isNotEmpty ? items.first.name : 'Meal');
    final needsReview = items.any((i) => i.needsConfirmation);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isPhoto) ...[
              _PhotoThumbnail(
                presenter: widget.presenter,
                relativePath: message.photoThumbnailPath!,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _subLabel(items, message.timestamp),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      if (items.isNotEmpty)
                        _SourceChip(source: items.first.estimationSource),
                      if (message.isPhoto)
                        _MetaChip(
                          icon: Icons.photo_camera_outlined,
                          label: 'photo',
                          color: cs.primary,
                        ),
                      if (needsReview)
                        _MetaChip(
                          icon: Icons.error_outline,
                          label: 'review',
                          color: cs.error,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  NumberFormat.decimalPattern().format(kcal),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'kcal',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            _MacroDots(p: p, c: c, f: f),
            const Spacer(),
            _IconTapTarget(
              icon: Icons.more_horiz,
              color: _menuOpen ? cs.primary : cs.onSurfaceVariant,
              tooltip: 'Entry actions',
              onTap: () => setState(() => _menuOpen = !_menuOpen),
            ),
          ],
        ),
        // Low-confidence: swap-to-alternative chips per flagged item.
        for (var i = 0; i < items.length; i++)
          if (items[i].alternatives.isNotEmpty)
            _AlternativesStrip(
              alternatives: items[i].alternatives,
              onTap: (altIndex) => widget.presenter
                  .swapChatFoodAlternative(message.id, i, altIndex),
            ),
        if (_menuOpen) ...[
          const SizedBox(height: 11),
          _ActionRow(
            children: [
              _ActionButton(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onTap: () => setState(() {
                  _editing = true;
                  _menuOpen = false;
                }),
              ),
              _ActionButton(
                icon: Icons.bookmark_border,
                label: 'Save',
                onTap: _saveAsTemplate,
              ),
              _ActionButton(
                icon: Icons.thumb_down_outlined,
                label: 'Wrong',
                onTap: _onDislike,
              ),
              _ActionButton(
                icon: Icons.delete_outline,
                label: 'Delete',
                danger: true,
                onTap: _onDelete,
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _subLabel(List<ChatFoodItem> items, DateTime timestamp) {
    final time = DateFormat('h:mm a').format(timestamp);
    if (items.length == 1 &&
        items.first.grams != null &&
        items.first.grams! > 0) {
      return '${_gramsLabel(items.first.grams!)} · $time';
    }
    final n = items.length;
    return '$n item${n == 1 ? '' : 's'} · $time';
  }

  String _gramsLabel(double g) {
    if (g >= 1000) return '${(g / 1000).toStringAsFixed(1)}kg';
    if (g == g.roundToDouble()) return '${g.round()}g';
    return '${g.toStringAsFixed(1)}g';
  }

  // ── Editing (inline per-item edit) ────────────────────────────────────────
  Widget _buildEditing(BuildContext context) {
    final message = widget.message;
    final cs = Theme.of(context).colorScheme;
    final items = message.foodItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Editing entry',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _FoodEditField(
                  controller: _controllers[i],
                  autofocus: i == 0,
                  presenter: widget.presenter,
                ),
              ),
              if (items.length > 1) ...[
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Remove this item',
                  icon: Icon(Icons.close, color: cs.error),
                  onPressed: () =>
                      widget.presenter.removeChatFoodItemAt(message.id, i),
                ),
              ],
            ],
          ),
          if (items[i].alternatives.isNotEmpty)
            _AlternativesStrip(
              alternatives: items[i].alternatives,
              onTap: (altIndex) => widget.presenter
                  .swapChatFoodAlternative(message.id, i, altIndex),
            ),
        ],
        const SizedBox(height: 12),
        _ActionRow(
          children: [
            if (_saving)
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.appColors.success,
                    ),
                  ),
                ),
              )
            else
              _ActionButton(
                icon: Icons.check,
                label: 'Save',
                accent: true,
                onTap: _save,
              ),
            _ActionButton(
              icon: Icons.close,
              label: 'Cancel',
              onTap: _cancel,
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Exercise entry card ────────────────────────────────────────────────────

class _ExerciseEntryCard extends StatefulWidget {
  final ChatMessage message;
  final NutritionPresenter presenter;
  const _ExerciseEntryCard({required this.message, required this.presenter});

  @override
  State<_ExerciseEntryCard> createState() => _ExerciseEntryCardState();
}

class _ExerciseEntryCardState extends State<_ExerciseEntryCard> {
  bool _menuOpen = false;

  Future<void> _onDelete() async {
    final messenger = ScaffoldMessenger.of(context);
    final msg = widget.message;
    final name = msg.exerciseEntry?.name ?? 'Exercise';
    await widget.presenter.removeChatMessage(msg.id);
    if (!mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed · $name'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.presenter.restoreChatMessage(msg),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.message.exerciseEntry!;
    final cs = Theme.of(context).colorScheme;

    return _CardShell(
      highlight: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.local_fire_department_outlined,
                  color: context.appColors.gold, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.statsLabel.isNotEmpty
                          ? '${e.statsLabel} · ${DateFormat('h:mm a').format(widget.message.timestamp)}'
                          : DateFormat('h:mm a')
                              .format(widget.message.timestamp),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '−${e.caloriesBurned}',
                    style: TextStyle(
                      color: context.appColors.success,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'kcal',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const Spacer(),
              _IconTapTarget(
                icon: Icons.more_horiz,
                color: _menuOpen ? cs.primary : cs.onSurfaceVariant,
                tooltip: 'Entry actions',
                onTap: () => setState(() => _menuOpen = !_menuOpen),
              ),
            ],
          ),
          if (_menuOpen) ...[
            const SizedBox(height: 11),
            _ActionRow(
              children: [
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  danger: true,
                  onTap: _onDelete,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared bits ────────────────────────────────────────────────────────────

/// Coloured-dot macro summary: ● {p}P ● {c}C ● {f}F.
class _MacroDots extends StatelessWidget {
  final double p;
  final double c;
  final double f;
  const _MacroDots({required this.p, required this.c, required this.f});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        _dot(context, cs.primary, '${p.round()}P'),
        const SizedBox(width: 13),
        _dot(context, context.appColors.gold, '${c.round()}C'),
        const SizedBox(width: 13),
        _dot(context, cs.error, '${f.round()}F'),
      ],
    );
  }

  Widget _dot(BuildContext context, Color color, String label) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Source-attribution chip built from an [EstimationSource]'s badge + colour.
class _SourceChip extends StatelessWidget {
  final EstimationSource source;
  const _SourceChip({required this.source});

  @override
  Widget build(BuildContext context) {
    if (!source.showBadge) return const SizedBox.shrink();
    final color = source.badgeColor(context);
    return _MetaChip(icon: _iconFor(source), label: source.badge, color: color);
  }

  IconData _iconFor(EstimationSource s) => switch (s) {
        EstimationSource.cloudAi ||
        EstimationSource.cloudAiFallback =>
          Icons.cloud_outlined,
        EstimationSource.localAi => Icons.phone_android_outlined,
        EstimationSource.photoAi => Icons.photo_camera_outlined,
        EstimationSource.personalDict => Icons.person_outline,
        EstimationSource.userManual => Icons.edit_outlined,
        EstimationSource.aiPerItem => Icons.auto_awesome_outlined,
        EstimationSource.keywordDensity => Icons.search,
        EstimationSource.db => Icons.storage_outlined,
      };
}

/// Small icon + label pill used for source/photo/review attribution.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A wrapping row of action buttons separated behind a top divider.
class _ActionRow extends StatelessWidget {
  final List<Widget> children;
  const _ActionRow({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spaced.add(Expanded(child: children[i]));
      if (i != children.length - 1) spaced.add(const SizedBox(width: 7));
    }
    return Container(
      padding: const EdgeInsets.only(top: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(children: spaced),
    );
  }
}

/// A single Edit/Save/Wrong/Delete action inside an [_ActionRow].
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool accent;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color fg;
    final Color bg;
    if (danger) {
      fg = cs.error;
      bg = cs.error.withValues(alpha: 0.12);
    } else if (accent) {
      fg = cs.onPrimary;
      bg = cs.primary;
    } else {
      fg = cs.onSurface;
      bg = cs.surfaceContainerHighest;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ≥44px tappable icon target.
class _IconTapTarget extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconTapTarget({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onTap,
      ),
    );
  }
}

/// Runner-up DB matches as tap-to-swap chips for a low-confidence item.
class _AlternativesStrip extends StatelessWidget {
  final List<ChatFoodAlternative> alternatives;
  final ValueChanged<int> onTap;
  const _AlternativesStrip({required this.alternatives, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not this? Try:',
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < alternatives.length; i++)
                ActionChip(
                  onPressed: () => onTap(i),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: cs.surfaceContainerHigh,
                  side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.6)),
                  label: Text(
                    '${alternatives[i].name} · ${alternatives[i].calories} kcal',
                    style: TextStyle(color: cs.onSurface, fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edit field with on-the-fly DB suggestions (ported from the chat card). Tap a
/// suggestion to fill the text; suggestions come from [NutritionPresenter.foodDb].
class _FoodEditField extends StatefulWidget {
  final TextEditingController controller;
  final bool autofocus;
  final NutritionPresenter presenter;
  const _FoodEditField({
    required this.controller,
    required this.autofocus,
    required this.presenter,
  });

  @override
  State<_FoodEditField> createState() => _FoodEditFieldState();
}

class _FoodEditFieldState extends State<_FoodEditField> {
  List<FoodDbEntry> _suggestions = const [];
  Timer? _debounce;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text.trim();
    if (text == _lastQuery) return;
    _lastQuery = text;
    _debounce?.cancel();
    if (text.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () => _runQuery(text));
  }

  Future<void> _runQuery(String q) async {
    final results = await widget.presenter.foodDb.search(q);
    if (!mounted || widget.controller.text.trim() != q) return;
    setState(() => _suggestions = results.take(5).toList(growable: false));
  }

  void _accept(FoodDbEntry entry) {
    // Strip USDA-style `, qualifier` commas so the NLP parser doesn't split
    // "oats rolled, dry" into two separate food items on submit.
    widget.controller.text = entry.name.replaceAll(', ', ' ');
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          style: TextStyle(color: cs.onSurface, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            fillColor: cs.surfaceContainerHighest,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.primary),
            ),
            hintText: 'e.g. 100g rice',
            hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _suggestions.length; i++)
                  InkWell(
                    onTap: () => _accept(_suggestions[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.search,
                              size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _suggestions[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: cs.onSurface, fontSize: 13),
                            ),
                          ),
                          Text(
                            _suggestions[i].densityLabel,
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Small tappable thumbnail shown on a photo-logged entry (Plan 029 §0.4).
/// Resolves the docs-relative path asynchronously; falls back to a camera glyph
/// while loading or if the file is missing.
class _PhotoThumbnail extends StatelessWidget {
  final NutritionPresenter presenter;
  final String relativePath;
  const _PhotoThumbnail({required this.presenter, required this.relativePath});

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.photo_camera_outlined,
              size: 18, color: cs.onSurfaceVariant),
        );

    return FutureBuilder<String?>(
      future: presenter.resolvePhotoThumbnail(relativePath),
      builder: (context, snap) {
        final path = snap.data;
        if (path == null) return placeholder();
        return GestureDetector(
          onTap: () => _showFull(context, path),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(path),
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder(),
            ),
          ),
        );
      },
    );
  }

  void _showFull(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
