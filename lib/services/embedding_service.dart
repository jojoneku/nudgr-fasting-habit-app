import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as fg;
import 'package:flutter_gemma/rag/embedding_models.dart' as fg_rag;

/// Wraps flutter_gemma's embedding model lifecycle.
///
/// Responsibilities:
///   - Install the embedding model + tokenizer (network download, gated by HF token)
///   - Load the active embedder
///   - Expose `embed()` and `embedBatch()` for the rest of the pipeline
///   - Track install / load state so callers can show download UI
///
/// Defaults to Gecko 110M quantized (145 MB, 768 dims, English) from
/// `litert-community/Gecko-110m-en`. flutter_gemma 0.12.6's EmbeddingModel enum
/// ships broken URLs (Google's repos publish .safetensors only, not .tflite,
/// and the Gecko enum points at `gecko.tflite` which doesn't exist — actual
/// filename is `Gecko_1024_quant.tflite`). We bypass the enum by passing the
/// concrete URLs directly.
class EmbeddingService {
  /// Resolves the HuggingFace read token at download time.
  /// Returns null if no token is available (offline + uncached).
  /// Lazy by design — the token is fetched from the server on each install
  /// attempt rather than bundled into the APK.
  final Future<String?> Function()? tokenProvider;

  /// Which embedder to install on first use (kept for `dimension` only;
  /// enum URLs are ignored — see [modelUrl] / [tokenizerUrl]).
  final fg_rag.EmbeddingModel modelChoice;

  /// Concrete HuggingFace URL for the .tflite model file.
  final String modelUrl;

  /// Concrete HuggingFace URL for the sentencepiece tokenizer file.
  final String tokenizerUrl;

  /// Display label for the model in Settings (e.g. "Gecko 110M (quant)").
  final String displayName;

  /// Approximate download size label, e.g. "145 MB".
  final String sizeLabel;

  EmbeddingService({
    this.tokenProvider,
    this.modelChoice = fg_rag.EmbeddingModel.gecko110M,
    this.modelUrl =
        'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_1024_quant.tflite',
    this.tokenizerUrl =
        'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model',
    this.displayName = 'Gecko 110M (quant)',
    this.sizeLabel = '145 MB',
  });

  fg.EmbeddingModel? _model;
  bool _isDownloading = false;
  int _downloadProgress = 0;
  bool _deviceIncompatible = false;

  // ── State getters ────────────────────────────────────────────────────────

  bool get isReady => _model != null && !_deviceIncompatible;
  bool get isInstalled => fg.FlutterGemma.hasActiveEmbedder();
  bool get isDownloading => _isDownloading;
  int get downloadProgress => _downloadProgress;
  bool get isDeviceIncompatible => _deviceIncompatible;

  /// Dimension of vectors this embedder produces.
  int get vectorDim => modelChoice.dimension;

  String get modelSizeLabel => sizeLabel;
  String get modelDisplayName => displayName;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call once at app startup. Loads an already-installed embedder silently.
  /// Safe to call when no embedder is installed yet — exits as a no-op.
  Future<void> init() async {
    try {
      if (!fg.FlutterGemma.hasActiveEmbedder()) return;
      await _loadActive();
    } catch (e) {
      _maybeMarkIncompatible(e);
      debugPrint('EmbeddingService: init failed: $e');
    }
  }

  /// Download + install the embedder, then load it. Idempotent.
  Future<void> downloadModel({void Function(int progress)? onProgress}) async {
    if (_isDownloading) return;
    _isDownloading = true;
    _downloadProgress = 0;

    try {
      if (fg.FlutterGemma.hasActiveEmbedder()) {
        await _loadActive();
        return;
      }

      // Two files to download — model + tokenizer. Combined progress is the
      // mean of the two reports.
      var modelPct = 0;
      var tokenizerPct = 0;
      void publish() {
        final combined = ((modelPct + tokenizerPct) / 2).round();
        if (combined != _downloadProgress) {
          _downloadProgress = combined;
          onProgress?.call(combined);
        }
      }

      final token = await tokenProvider?.call();
      await fg.FlutterGemma.installEmbedder()
          .modelFromNetwork(modelUrl, token: token)
          .tokenizerFromNetwork(
            tokenizerUrl,
            token: token,
          )
          .withModelProgress((p) {
        modelPct = p;
        publish();
      }).withTokenizerProgress((p) {
        tokenizerPct = p;
        publish();
      }).install();

      await _loadActive();
    } catch (e) {
      _maybeMarkIncompatible(e);
      debugPrint('EmbeddingService.downloadModel failed: $e');
      rethrow;
    } finally {
      _isDownloading = false;
    }
  }

  Future<void> _loadActive() async {
    try {
      _model = await fg.FlutterGemma.getActiveEmbedder(
        preferredBackend: fg.PreferredBackend.gpu,
      );
    } catch (_) {
      try {
        _model = await fg.FlutterGemma.getActiveEmbedder(
          preferredBackend: fg.PreferredBackend.cpu,
        );
      } catch (e) {
        _maybeMarkIncompatible(e);
        rethrow;
      }
    }
  }

  void _maybeMarkIncompatible(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('opencl') ||
        msg.contains('can not find') ||
        msg.contains('unsupported')) {
      _deviceIncompatible = true;
    }
  }

  Future<void> dispose() async {
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
  }

  // ── Embedding ─────────────────────────────────────────────────────────────

  /// Returns a single embedding vector. Throws [StateError] if not ready.
  Future<List<double>> embed(String text) async {
    final m = _model;
    if (m == null) {
      throw StateError('EmbeddingService not ready. Call downloadModel first.');
    }
    return m.generateEmbedding(text);
  }

  /// Batch variant. Falls back to sequential calls if the underlying plugin
  /// does not implement `generateEmbeddings` for this backend.
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final m = _model;
    if (m == null) {
      throw StateError('EmbeddingService not ready. Call downloadModel first.');
    }
    if (texts.isEmpty) return const [];
    try {
      return await m.generateEmbeddings(texts);
    } catch (e) {
      debugPrint(
        'EmbeddingService: batch embed failed, falling back sequential: $e',
      );
      final out = <List<double>>[];
      for (final t in texts) {
        out.add(await m.generateEmbedding(t));
      }
      return out;
    }
  }
}
