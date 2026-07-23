import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../presenters/ledger_presenter.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../../services/image_compressor.dart';
import '../../nutrition/food_photo_sheet.dart';

/// Unified "snap a photo to log" entry point shared by the ledger and the hub
/// quick-log bar. Step 1 asks what the photo is: a **receipt** (→ a ledger
/// expense) or a **meal** (→ the existing nutrition photo flow). Receipts are
/// scanned into the ledger's confirm-before-commit pipeline, so the inline chat
/// panel on the parent surface shows the "Log it" card once this sheet closes.
///
/// [nutrition] is optional — when absent (finance-only surfaces) the chooser is
/// skipped and it goes straight to the receipt flow.
Future<void> showPhotoLogSheet(
  BuildContext context, {
  required LedgerPresenter ledger,
  NutritionPresenter? nutrition,
  ImageCompressor compressor = const ImageCompressor(),
}) async {
  if (nutrition == null) {
    await _runReceiptFlow(context, ledger, compressor);
    return;
  }

  final kind = await showModalBottomSheet<_PhotoKind>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _KindPicker(),
  );
  if (kind == null || !context.mounted) return;

  if (kind == _PhotoKind.meal) {
    await showFoodPhotoSheet(context, nutrition);
  } else {
    await _runReceiptFlow(context, ledger, compressor);
  }
}

enum _PhotoKind { receipt, meal }

/// Loops so "Retake" from the preview returns to the source picker.
Future<void> _runReceiptFlow(
  BuildContext context,
  LedgerPresenter ledger,
  ImageCompressor compressor,
) async {
  while (true) {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _SourcePicker(),
    );
    if (source == null || !context.mounted) return;

    final XFile? picked = await _pick(source);
    if (picked == null || !context.mounted) return;

    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;

    final outcome = await showModalBottomSheet<_ReceiptOutcome>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      useSafeArea: true,
      builder: (_) => _ReceiptPreviewSheet(
        bytes: bytes,
        ledger: ledger,
        compressor: compressor,
      ),
    );
    if (outcome != _ReceiptOutcome.retake) return;
    if (!context.mounted) return;
  }
}

enum _ReceiptOutcome { retake, done }

Future<XFile?> _pick(ImageSource source) async {
  try {
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

class _KindPicker extends StatelessWidget {
  const _KindPicker();

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
              "What's in the photo?",
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _Tile(
              icon: Icons.receipt_long_outlined,
              label: 'Receipt',
              sub: 'Log an expense from a receipt or bill',
              onTap: () => Navigator.of(context).pop(_PhotoKind.receipt),
            ),
            const SizedBox(height: 9),
            _Tile(
              icon: Icons.restaurant_outlined,
              label: 'Meal',
              sub: 'Estimate calories from a food photo',
              onTap: () => Navigator.of(context).pop(_PhotoKind.meal),
            ),
          ],
        ),
      ),
    );
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
              'Scan a receipt',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _Tile(
              icon: Icons.photo_camera_outlined,
              label: 'Take photo',
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            const SizedBox(height: 9),
            _Tile(
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, color: cs.primary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub!,
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptPreviewSheet extends StatefulWidget {
  const _ReceiptPreviewSheet({
    required this.bytes,
    required this.ledger,
    required this.compressor,
  });

  final Uint8List bytes;
  final LedgerPresenter ledger;
  final ImageCompressor compressor;

  @override
  State<_ReceiptPreviewSheet> createState() => _ReceiptPreviewSheetState();
}

class _ReceiptPreviewSheetState extends State<_ReceiptPreviewSheet> {
  final _noteCtrl = TextEditingController();
  bool _scanning = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });

    Uint8List upload;
    try {
      upload = await widget.compressor.compressForUpload(widget.bytes);
    } catch (_) {
      upload = widget.bytes; // fall back to the original bytes
    }
    if (!mounted) return;

    final note = _noteCtrl.text.trim();
    final outcome = await widget.ledger.logReceiptPhoto(
      upload,
      'image/jpeg',
      note: note.isEmpty ? null : note,
    );
    if (!mounted) return;

    if (outcome == ReceiptScanOutcome.seeded) {
      // The inline chat panel on the parent surface now shows the confirm card.
      Navigator.of(context).pop(_ReceiptOutcome.done);
      return;
    }
    setState(() {
      _scanning = false;
      _error = _messageFor(outcome);
    });
  }

  String _messageFor(ReceiptScanOutcome outcome) => switch (outcome) {
        ReceiptScanOutcome.notReceipt =>
          "That doesn't look like a receipt. Try a clearer, straight-on photo.",
        ReceiptScanOutcome.rateLimited =>
          'Daily AI limit reached. Try again tomorrow.',
        ReceiptScanOutcome.networkError =>
          'Couldn\'t reach the scanner. Check your connection and try again.',
        ReceiptScanOutcome.unavailable =>
          'Receipt scanning needs Cloud AI. Sign in and enable it in Settings.',
        ReceiptScanOutcome.serverError ||
        ReceiptScanOutcome.failed =>
          'Couldn\'t read that receipt. Try again in a moment.',
        ReceiptScanOutcome.seeded => '',
      };

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
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
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
                      Icon(Icons.receipt_long_outlined,
                          size: 11, color: Colors.white),
                      SizedBox(width: 5),
                      Text('Receipt',
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
            controller: _noteCtrl,
            enabled: !_scanning,
            style: TextStyle(color: cs.onSurface, fontSize: 14),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Add a note (optional) — e.g. "split with a friend"',
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
            onSubmitted: (_) => _scan(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 96,
                child: OutlinedButton(
                  onPressed: _scanning
                      ? null
                      : () => Navigator.of(context).pop(_ReceiptOutcome.retake),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('Retake'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _scan,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: _scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(_scanning ? 'Reading…' : 'Scan receipt'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
