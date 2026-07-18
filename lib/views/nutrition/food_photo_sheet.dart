import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_colors.dart';
import '../../presenters/nutrition_presenter.dart';

/// Plan 029 — photo food logging entry point (restyled to Nudgr "More" spec).
///
/// Three steps: pick a source (Take photo / Choose from gallery), preview the
/// shot with an optional note, then review the estimate before logging. "Retake"
/// loops back to the source picker; "Analyze photo" runs the vision parse
/// ([NutritionPresenter.resolvePhotoPreview]) into a pending estimate shown in
/// the same sheet; "Log it" commits it ([commitPendingChat]) and it appears in
/// the log, while "Edit" returns to the preview.
Future<void> showFoodPhotoSheet(
  BuildContext context,
  NutritionPresenter presenter,
) async {
  // Loop so "Retake" from the preview returns to the source picker.
  while (true) {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const _SourcePicker(),
    );
    if (source == null || !context.mounted) return;

    final XFile? picked = await _pick(source);
    if (picked == null || !context.mounted) return;

    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;

    final outcome = await showModalBottomSheet<_PreviewOutcome>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      useSafeArea: true,
      builder: (ctx) => _PhotoPreviewSheet(bytes: bytes, presenter: presenter),
    );
    if (outcome != _PreviewOutcome.retake) return;
    if (!context.mounted) return;
  }
}

/// Result of the preview sheet — whether the user asked to retake or the flow
/// is otherwise finished (logged or dismissed).
enum _PreviewOutcome { retake, done }

Future<XFile?> _pick(ImageSource source) async {
  try {
    // Cap the source resolution; the presenter compresses again to 1024px.
    return await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
  } catch (_) {
    // Permission denied or no camera — surfaced as a no-op (sheet closes).
    return null;
  }
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Log a meal photo',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _SourceTile(
              icon: Icons.photo_camera_outlined,
              label: 'Take photo',
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            const SizedBox(height: 9),
            _SourceTile(
              icon: Icons.image_outlined,
              label: 'Choose from gallery',
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, color: cs.primary, size: 22),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPreviewSheet extends StatefulWidget {
  final Uint8List bytes;
  final NutritionPresenter presenter;
  const _PhotoPreviewSheet({required this.bytes, required this.presenter});

  @override
  State<_PhotoPreviewSheet> createState() => _PhotoPreviewSheetState();
}

class _PhotoPreviewSheetState extends State<_PhotoPreviewSheet> {
  final _captionCtrl = TextEditingController();
  bool _submitting = false;
  bool _showEstimate = false;
  bool _committing = false; // guards double-tap on "Log it"
  String? _error;

  @override
  void dispose() {
    // Drop any un-logged photo estimate (+ its orphan thumbnail) on close.
    widget.presenter.discardPendingChat();
    _captionCtrl.dispose();
    super.dispose();
  }

  /// Analyse the photo into a pending estimate — does NOT log yet.
  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    await widget.presenter.resolvePhotoPreview(
      widget.bytes,
      caption:
          _captionCtrl.text.trim().isEmpty ? null : _captionCtrl.text.trim(),
    );
    if (!mounted) return;
    final err = widget.presenter.photoParseError;
    if (err != null) {
      setState(() {
        _submitting = false;
        _error = err;
      });
    } else if (widget.presenter.hasPendingChat) {
      setState(() {
        _submitting = false;
        _showEstimate = true;
      });
    } else {
      Navigator.of(context).pop(_PreviewOutcome.done);
    }
  }

  /// Commit the reviewed photo estimate to the log, then close.
  Future<void> _logPhoto() async {
    if (_committing) return; // guard double-tap
    _committing = true;
    final messenger = ScaffoldMessenger.of(context);
    final kcal = widget.presenter.pendingChatTotalCalories;
    final id = await widget.presenter.commitPendingChat();
    if (!mounted) return;
    Navigator.of(context).pop(_PreviewOutcome.done);
    if (id != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Logged · $kcal kcal'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => widget.presenter.removeChatMessage(id),
            ),
          ),
        );
    }
  }

  /// Drop the estimate and return to the photo preview to re-analyse or retake.
  void _editPhoto() {
    widget.presenter.discardPendingChat();
    setState(() => _showEstimate = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_showEstimate && widget.presenter.hasPendingChat)
            ..._buildEstimate(cs)
          else ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Image.memory(
                      widget.bytes,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_camera_outlined,
                            size: 11, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Meal photo',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _captionCtrl,
              enabled: !_submitting,
              style: TextStyle(color: cs.onSurface, fontSize: 14),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Add a note (optional) — e.g. "no rice in mine"',
                hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: cs.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () =>
                            Navigator.of(context).pop(_PreviewOutcome.retake),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(_submitting ? 'Analyzing…' : 'Analyze photo'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The "Photo · estimate" review step — detected items + macros + Log it/Edit
  /// (mirrors the reference and the text composer's estimate card).
  List<Widget> _buildEstimate(ColorScheme cs) {
    final entries = widget.presenter.pendingChatEntries;
    final totalKcal = widget.presenter.pendingChatTotalCalories;
    final macros = widget.presenter.pendingChatMacros;
    final p = macros.protein;
    final c = macros.carbs;
    final f = macros.fat;

    return [
      Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(widget.bytes,
                width: 46, height: 46, fit: BoxFit.cover),
          ),
          const SizedBox(width: 11),
          Icon(Icons.auto_awesome, size: 13, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            'FROM PHOTO',
            style: TextStyle(
              color: cs.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name,
                              style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(_macroSub(e.protein, e.carbs, e.fat),
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 10.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${e.calories}',
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 11),
            Row(
              children: [
                _dot(cs, cs.primary, '${p.round()}P'),
                const SizedBox(width: 11),
                _dot(cs, context.appColors.gold, '${c.round()}C'),
                const SizedBox(width: 11),
                _dot(cs, cs.error, '${f.round()}F'),
                const Spacer(),
                Text('$totalKcal ',
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                Text('kcal',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _logPhoto,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Log it',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 104,
            child: OutlinedButton.icon(
              onPressed: _editPhoto,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('Edit'),
            ),
          ),
        ],
      ),
    ];
  }

  String _macroSub(double? p, double? c, double? f) {
    final parts = <String>[];
    if (p != null) parts.add('P${p.round()}');
    if (c != null) parts.add('C${c.round()}');
    if (f != null) parts.add('F${f.round()}');
    return parts.join(' · ');
  }

  Widget _dot(ColorScheme cs, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      );
}
