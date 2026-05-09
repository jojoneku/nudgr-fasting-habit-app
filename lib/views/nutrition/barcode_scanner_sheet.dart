import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../presenters/nutrition_presenter.dart';
import '../../services/open_food_facts_service.dart';

/// Two-step flow: scan a barcode, then preview + confirm before logging.
///
/// 1. [_ScannerView] opens a fullscreen camera. On first detection it pops
///    with the barcode string.
/// 2. [_PreviewSheet] looks the barcode up against OpenFoodFacts, shows the
///    parsed product + a serving-size field, and on confirm calls
///    [NutritionPresenter.logScannedProduct].
///
/// Public entry point is [showBarcodeScanFlow].
Future<void> showBarcodeScanFlow(
  BuildContext context, {
  required NutritionPresenter presenter,
}) async {
  final barcode = await Navigator.of(context).push<String?>(
    MaterialPageRoute(
      builder: (_) => const _ScannerView(),
      fullscreenDialog: true,
    ),
  );
  if (barcode == null || barcode.isEmpty) return;
  if (!context.mounted) return;
  await _showPreviewSheet(context, presenter: presenter, barcode: barcode);
}

class _ScannerView extends StatefulWidget {
  const _ScannerView();

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  // Restrict to common 1D retail barcodes; QR/2D would still scan but the
  // UI prompt is barcode-shaped so keep the formats focused.
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _popped = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_popped) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    _popped = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Toggle torch',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Reticle — loose visual cue, not a hard scan region.
          Center(
            child: Container(
              width: 240,
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: cs.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Point camera at barcode',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showPreviewSheet(
  BuildContext context, {
  required NutritionPresenter presenter,
  required String barcode,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PreviewSheet(presenter: presenter, barcode: barcode),
  );
}

class _PreviewSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  final String barcode;
  const _PreviewSheet({required this.presenter, required this.barcode});

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  late Future<BarcodeLookupResult?> _future;
  final _gramsCtrl = TextEditingController(text: '100');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = widget.presenter.lookupBarcode(widget.barcode);
  }

  @override
  void dispose() {
    _gramsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm(BarcodeLookupResult result) async {
    final grams = double.tryParse(_gramsCtrl.text.trim());
    if (grams == null || grams <= 0) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    await widget.presenter.logScannedProduct(result, grams: grams);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Logged ${result.displayName}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: FutureBuilder<BarcodeLookupResult?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final result = snapshot.data;
          if (result == null) {
            return _NotFoundView(barcode: widget.barcode);
          }
          return _ResultView(
            result: result,
            gramsCtrl: _gramsCtrl,
            saving: _saving,
            onConfirm: () => _confirm(result),
            onCancel: () => Navigator.of(context).pop(),
            cs: cs,
          );
        },
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final BarcodeLookupResult result;
  final TextEditingController gramsCtrl;
  final bool saving;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final ColorScheme cs;

  const _ResultView({
    required this.result,
    required this.gramsCtrl,
    required this.saving,
    required this.onConfirm,
    required this.onCancel,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final entry = result.entry;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.displayName,
          style: TextStyle(
              color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${entry.caloriesPer100g.round()} kcal · '
          'P${entry.proteinPer100g?.toStringAsFixed(1) ?? "—"}g · '
          'C${entry.carbsPer100g?.toStringAsFixed(1) ?? "—"}g · '
          'F${entry.fatPer100g?.toStringAsFixed(1) ?? "—"}g  per 100g',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: gramsCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Grams',
            suffixText: 'g',
            filled: true,
            fillColor: cs.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: saving ? null : onCancel,
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: saving ? null : onConfirm,
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotFoundView extends StatelessWidget {
  final String barcode;
  const _NotFoundView({required this.barcode});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Barcode not found',
            style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'OpenFoodFacts doesn\'t have $barcode yet, or the entry is missing '
          'nutrition data. Try typing the food name in the chat instead.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ),
      ],
    );
  }
}
