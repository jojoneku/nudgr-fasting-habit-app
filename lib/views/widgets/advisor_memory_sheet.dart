import 'package:flutter/material.dart';

import '../../presenters/ai_coach_presenter.dart';

/// User-curated memory for the financial advisor: goals, risk tolerance, and
/// freeform notes the user wants the advisor to keep in mind, plus controls to
/// clear the conversation history. All edits persist through the presenter.
class AdvisorMemorySheet extends StatelessWidget {
  final AiCoachPresenter presenter;
  const AdvisorMemorySheet({super.key, required this.presenter});

  static Future<void> show(BuildContext context, AiCoachPresenter presenter) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdvisorMemorySheet(presenter: presenter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListenableBuilder(
          listenable: presenter,
          builder: (context, _) {
            final profile = presenter.advisorProfile;
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                  'What your advisor remembers',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You control this. The advisor uses it as context in every chat.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 20),

                // ── Goals ──
                const _SectionLabel('Goals'),
                ...profile.goals.map((g) => _RemovableRow(
                      label: g,
                      onRemove: () => presenter.removeAdvisorGoal(g),
                    )),
                _AddField(
                  hint: 'Add a goal (e.g. ₱100k emergency fund)',
                  onSubmit: presenter.addAdvisorGoal,
                ),
                const SizedBox(height: 20),

                // ── Risk tolerance ──
                const _SectionLabel('Risk tolerance'),
                _RiskToleranceField(
                  value: profile.riskTolerance,
                  onChanged: presenter.setAdvisorRiskTolerance,
                ),
                const SizedBox(height: 20),

                // ── Notes ──
                const _SectionLabel('Notes'),
                ...profile.facts.map((f) => _RemovableRow(
                      label: f,
                      onRemove: () => presenter.removeAdvisorFact(f),
                    )),
                _AddField(
                  hint: 'Add a note (e.g. supports parents monthly)',
                  onSubmit: presenter.addAdvisorFact,
                ),
                const SizedBox(height: 28),

                // ── Danger zone ──
                if (!profile.isEmpty)
                  TextButton.icon(
                    onPressed: () => presenter.clearAdvisorProfile(),
                    icon: Icon(Icons.delete_outline, color: cs.error, size: 18),
                    label: Text('Clear all memory',
                        style: TextStyle(color: cs.error)),
                  ),
                TextButton.icon(
                  onPressed: () {
                    presenter.clearHistory();
                    Navigator.of(context).maybePop();
                  },
                  icon: Icon(Icons.forum_outlined,
                      color: cs.onSurfaceVariant, size: 18),
                  label: Text('Clear conversation history',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RemovableRow extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _RemovableRow({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: cs.onSurface, fontSize: 14)),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
            tooltip: 'Remove',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AddField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onSubmit;
  const _AddField({required this.hint, required this.onSubmit});

  @override
  State<_AddField> createState() => _AddFieldState();
}

class _AddFieldState extends State<_AddField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onSubmit(t);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: cs.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            icon: const Icon(Icons.add),
            color: cs.primary,
            tooltip: 'Add',
            onPressed: _submit,
          ),
        ),
      ],
    );
  }
}

class _RiskToleranceField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _RiskToleranceField({required this.value, required this.onChanged});

  @override
  State<_RiskToleranceField> createState() => _RiskToleranceFieldState();
}

class _RiskToleranceFieldState extends State<_RiskToleranceField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _ctrl,
      textInputAction: TextInputAction.done,
      onSubmitted: widget.onChanged,
      onTapOutside: (_) => widget.onChanged(_ctrl.text),
      style: TextStyle(color: cs.onSurface, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'e.g. conservative, moderate builder, aggressive',
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
