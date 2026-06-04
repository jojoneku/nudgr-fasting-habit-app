import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../presenters/nutrition_presenter.dart';

/// Plan 029 — photo food logging entry point.
///
/// Two steps: pick a source (camera / gallery), then preview the shot with an
/// optional caption before sending it to the vision endpoint. The parse runs
/// inside the preview sheet so progress and errors stay local; on success the
/// items appear in the chat feed via [NutritionPresenter.parsePhoto].
Future<void> showFoodPhotoSheet(
  BuildContext context,
  NutritionPresenter presenter,
) async {
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

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    useSafeArea: true,
    builder: (ctx) => _PhotoPreviewSheet(bytes: bytes, presenter: presenter),
  );
}

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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Log a meal photo',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _SourceTile(
              icon: Icons.photo_camera_outlined,
              label: 'Take photo',
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            const SizedBox(height: 8),
            _SourceTile(
              icon: Icons.photo_library_outlined,
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
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(color: cs.onSurface, fontSize: 15),
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
  String? _error;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    await widget.presenter.parsePhoto(
      widget.bytes,
      caption:
          _captionCtrl.text.trim().isEmpty ? null : _captionCtrl.text.trim(),
    );
    if (!mounted) return;
    final err = widget.presenter.photoParseError;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _submitting = false;
        _error = err;
      });
    }
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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.memory(
                widget.bytes,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
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
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Log'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
