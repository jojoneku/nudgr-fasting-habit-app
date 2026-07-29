import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../presenters/ledger_presenter.dart';
import '../../../services/image_compressor.dart';
import '../../../utils/app_radii.dart';
import '../design/web_breakpoints.dart';

/// Scan a receipt into an expense, from the desktop.
///
/// The mobile `photo_log_sheet.dart` can't be reused: it imports
/// `NutritionPresenter` for its meal branch, which the finance-only web app has
/// no presenter for. This is the receipt path alone, with drag-and-drop as the
/// primary interaction — on a desktop with a folder of scans open that beats a
/// camera-first flow anyway — and a file picker as the fallback.
///
/// The scan itself is unchanged: [LedgerPresenter.logReceiptPhoto] is already
/// cloud-only and seeds the same confirm-before-commit pipeline the typed Quick
/// Add uses, so nothing is written without the user confirming.
Future<void> showWebReceiptDialog(
  BuildContext context, {
  required LedgerPresenter ledger,
  ImageCompressor compressor = const ImageCompressor(),
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _WebReceiptDialog(ledger: ledger, compressor: compressor),
  );
}

class _WebReceiptDialog extends StatefulWidget {
  final LedgerPresenter ledger;
  final ImageCompressor compressor;

  const _WebReceiptDialog({required this.ledger, required this.compressor});

  @override
  State<_WebReceiptDialog> createState() => _WebReceiptDialogState();
}

class _WebReceiptDialogState extends State<_WebReceiptDialog> {
  Uint8List? _bytes;
  bool _busy = false;
  String? _error;
  bool _dragging = false;

  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't read that file.");
    }
  }

  Future<void> _scan() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    Uint8List payload = bytes;
    try {
      payload = await widget.compressor.compressForUpload(bytes);
    } catch (_) {
      // Compression is an optimisation, not a requirement — desktop uploads
      // aren't bandwidth-constrained, so fall back to the original bytes
      // rather than failing the scan.
    }

    final outcome = await widget.ledger.logReceiptPhoto(payload, 'image/jpeg');
    if (!mounted) return;

    if (outcome == ReceiptScanOutcome.seeded) {
      // The Ledger page's confirm card now holds the pending expense.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = _messageFor(outcome);
    });
  }

  /// Same wording as the mobile receipt sheet, so a failure reads identically
  /// on both platforms.
  String _messageFor(ReceiptScanOutcome outcome) => switch (outcome) {
        ReceiptScanOutcome.notReceipt =>
          "That doesn't look like a receipt. Try a clearer, straight-on scan.",
        ReceiptScanOutcome.rateLimited =>
          'Daily AI limit reached. Try again tomorrow.',
        ReceiptScanOutcome.networkError =>
          "Couldn't reach the scanner. Check your connection and try again.",
        ReceiptScanOutcome.unavailable =>
          'Receipt scanning needs Cloud AI. Make sure you are signed in.',
        ReceiptScanOutcome.serverError ||
        ReceiptScanOutcome.failed =>
          "Couldn't read that receipt. Try again in a moment.",
        ReceiptScanOutcome.seeded => '',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      title: const Text('Scan a receipt'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DropTarget(
              dragging: _dragging,
              bytes: _bytes,
              onDraggingChanged: (v) => setState(() => _dragging = v),
              onDropped: (bytes) => setState(() {
                _bytes = bytes;
                _error = null;
              }),
              onBrowse: _pickFile,
            ),
            if (_error != null) ...[
              const SizedBox(height: WebInsets.md),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: WebInsets.md),
            Text(
              'The amount and merchant are read from the receipt, then shown '
              'for you to confirm before anything is logged.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _bytes == null || _busy ? null : _scan,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Scan'),
        ),
      ],
    );
  }
}

/// The dashed drop zone. Shows a thumbnail once an image is staged.
class _DropTarget extends StatelessWidget {
  final bool dragging;
  final Uint8List? bytes;
  final ValueChanged<bool> onDraggingChanged;
  final ValueChanged<Uint8List> onDropped;
  final VoidCallback onBrowse;

  const _DropTarget({
    required this.dragging,
    required this.bytes,
    required this.onDraggingChanged,
    required this.onDropped,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DropTarget(
      onDragEntered: (_) => onDraggingChanged(true),
      onDragExited: (_) => onDraggingChanged(false),
      onDragDone: (detail) async {
        onDraggingChanged(false);
        final file = detail.files.firstOrNull;
        if (file == null) return;
        onDropped(await file.readAsBytes());
      },
      // Self-heal the highlight. desktop_drop's web handler does
      // `item.webkitGetAsEntry()!` and only logs on failure, so dragging
      // anything that is not a file entry — a text selection, a link — throws
      // inside the plugin: no drop, and no `onDragExited` either, which would
      // otherwise strand this target in its highlighted state. Leaving the
      // pointer clears it.
      child: MouseRegion(
        onExit: (_) {
          if (dragging) onDraggingChanged(false);
        },
        child: InkWell(
          onTap: onBrowse,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: dragging
                  ? cs.primary.withValues(alpha: 0.08)
                  : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: dragging
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: bytes != null
                ? Image.memory(bytes!, fit: BoxFit.contain)
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 32, color: cs.onSurfaceVariant),
                        const SizedBox(height: WebInsets.sm),
                        Text(
                          'Drop a receipt image here',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: WebInsets.xs),
                        Text(
                          'or click to browse',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
