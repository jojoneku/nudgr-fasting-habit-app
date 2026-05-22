import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as fg;
import 'package:path_provider/path_provider.dart';

import '../models/food_db_entry.dart';
import '../models/food_search_candidate.dart';
import '../models/index_progress.dart';
import 'embedding_service.dart';
import 'food_db_service.dart';
import 'storage_service.dart';
import 'vector_bundle_service.dart';

/// Orchestrates RAG food search:
///   1. Manages the persistent on-device vector store (flutter_gemma's HNSW)
///   2. Builds a resumable index over `food_db.sqlite` rows
///   3. Serves [search] queries by hydrating [RetrievalResult] → [FoodDbEntry]
///
/// The vector store path is `<appDocs>/food_vectors.sqlite`. We never write
/// to the read-only `food_db_v4.sqlite` asset.
///
/// Lifecycle:
///   - Construct with deps (no I/O).
///   - Call [init] once after [EmbeddingService.init].
///   - Optionally call [buildIndex] to start (or resume) the index build.
///   - Call [search] for queries — returns empty list when not [isReady].
class FoodSemanticSearchService {
  final EmbeddingService _embedder;
  final FoodDbService _foodDb;
  final StorageService _storage;
  final fg.FlutterGemmaPlugin _plugin;

  FoodSemanticSearchService({
    required EmbeddingService embedder,
    required FoodDbService foodDb,
    required StorageService storage,
    fg.FlutterGemmaPlugin? plugin,
  })  : _embedder = embedder,
        _foodDb = foodDb,
        _storage = storage,
        _plugin = plugin ?? fg.FlutterGemmaPlugin.instance;

  // ── State ─────────────────────────────────────────────────────────────────

  bool _isVectorStoreInitialized = false;
  bool _isIndexing = false;
  IndexProgress _progress = const IndexProgress.empty();
  final _progressController = StreamController<IndexProgress>.broadcast();

  /// True once both the vector store has been initialised AND the embedder
  /// is ready. Search calls return empty when this is false.
  bool get isReady =>
      _isVectorStoreInitialized && _embedder.isReady && _progress.indexed > 0;

  bool get isIndexing => _isIndexing;
  IndexProgress get progress => _progress;
  Stream<IndexProgress> get progressStream => _progressController.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialise the vector store (creates the SQLite file on first run) and
  /// load any persisted progress. Idempotent.
  Future<void> init() async {
    if (_isVectorStoreInitialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}${Platform.pathSeparator}food_vectors.sqlite';
      await _plugin.initializeVectorStore(path);
      _plugin.enableHnsw = true;
      _isVectorStoreInitialized = true;
      _progress = await _storage.loadFoodIndexProgress();
      _progressController.add(_progress);
    } catch (e) {
      debugPrint('FoodSemanticSearchService.init failed: $e');
    }
  }

  /// Build (or resume) the food vector index.
  ///
  /// Idempotent and resumable — successive calls skip already-embedded rows
  /// based on [IndexProgress.lastFoodId]. Returns when the build is complete
  /// or aborts (cancellation, embedder failure, etc.).
  Future<void> buildIndex({
    int batchSize = 32,
    void Function(IndexProgress)? onProgress,
  }) async {
    if (_isIndexing) return;
    if (!_isVectorStoreInitialized) await init();
    if (!_embedder.isReady) {
      debugPrint('FoodSemanticSearchService: embedder not ready; skip build');
      return;
    }

    _isIndexing = true;

    try {
      final total = await _foodDb.totalRowCount();
      if (total == 0) {
        debugPrint(
            'FoodSemanticSearchService: food_db has 0 rows — skipping build');
        return;
      }

      // Reset total each run in case the DB changed underneath us.
      _progress = _progress.copyWith(total: total);
      _publish(onProgress);

      String? cursor = _progress.isComplete ? null : _progress.lastFoodId;
      // If we were marked complete but actually have new rows, restart at the
      // last id (incremental top-up).
      if (_progress.isComplete && _progress.indexed >= total) {
        return; // truly done
      }

      while (true) {
        final page = await _foodDb.getAllForIndex(
          afterId: cursor,
          limit: batchSize,
        );
        if (page.isEmpty) break;

        final texts = page.map(_documentTextFor).toList();
        final List<List<double>> vectors;
        try {
          vectors = await _embedder.embedBatch(texts);
        } catch (e) {
          debugPrint('FoodSemanticSearchService: embed batch failed: $e');
          break; // bail; resume on next call
        }

        if (vectors.length != page.length) {
          debugPrint(
            'FoodSemanticSearchService: vector/page length mismatch — '
            'expected ${page.length}, got ${vectors.length}',
          );
          break;
        }

        for (var i = 0; i < page.length; i++) {
          final entry = page[i];
          await _plugin.addDocumentWithEmbedding(
            id: entry.id,
            content: texts[i],
            embedding: vectors[i],
            metadata: jsonEncode(_metadataFor(entry)),
          );
        }

        cursor = page.last.id;
        _progress = _progress.copyWith(
          indexed: _progress.indexed + page.length,
          lastFoodId: cursor,
          total: total,
        );
        await _storage.saveFoodIndexProgress(_progress);
        _publish(onProgress);

        if (page.length < batchSize) break;
      }

      _progress = _progress.copyWith(
        isComplete: true,
        completedAt: DateTime.now(),
      );
      await _storage.saveFoodIndexProgress(_progress);
      _publish(onProgress);
    } finally {
      _isIndexing = false;
    }
  }

  /// Wipe the vector store and progress, then call [buildIndex] again.
  /// Used by Settings ("Rebuild search index") and on `food_db` version bumps.
  Future<void> rebuildIndex({
    int batchSize = 32,
    void Function(IndexProgress)? onProgress,
  }) async {
    if (_isIndexing) return;
    try {
      await _plugin.clearVectorStore();
    } catch (e) {
      debugPrint('FoodSemanticSearchService.clear failed: $e');
    }
    _progress = const IndexProgress.empty();
    await _storage.clearFoodIndexProgress();
    _publish(onProgress);
    await buildIndex(batchSize: batchSize, onProgress: onProgress);
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Returns up to [k] candidates ranked by cosine similarity descending.
  /// Returns empty list when [isReady] is false or the underlying call fails.
  Future<List<FoodSearchCandidate>> search(String query, {int k = 5}) async {
    if (!isReady) return const [];
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final results = await _plugin.searchSimilar(
        query: trimmed,
        topK: k,
      );
      if (results.isEmpty) return const [];

      // Try to hydrate from the encoded metadata first — fastest path.
      final hydrated = <FoodSearchCandidate>[];
      final missingIds = <String>[];
      for (final r in results) {
        final entry = _entryFromMetadata(r.id, r.metadata);
        if (entry != null) {
          hydrated.add(FoodSearchCandidate(
            entry: entry,
            score: r.similarity,
            source: SearchSource.semantic,
          ));
        } else {
          missingIds.add(r.id);
        }
      }

      // Fallback: anything we couldn't hydrate from metadata, look up in DB.
      if (missingIds.isNotEmpty) {
        final fromDb = await _foodDb.getByIds(missingIds);
        final byId = {for (final e in fromDb) e.id: e};
        for (final r in results) {
          if (byId.containsKey(r.id) &&
              !hydrated.any((c) => c.entry.id == r.id)) {
            hydrated.add(FoodSearchCandidate(
              entry: byId[r.id]!,
              score: r.similarity,
              source: SearchSource.semantic,
            ));
          }
        }
      }

      // searchSimilar already returns ranked, but reapply to be safe after
      // the dual-source merge above.
      hydrated.sort((a, b) => b.score.compareTo(a.score));
      return hydrated.take(k).toList(growable: false);
    } catch (e) {
      debugPrint('FoodSemanticSearchService.search failed: $e');
      return const [];
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Document text to embed — `<name> (<category>)` per spec.
  String _documentTextFor(FoodDbEntry e) {
    if (e.category == null || e.category!.trim().isEmpty) return e.name;
    return '${e.name} (${e.category})';
  }

  Map<String, dynamic> _metadataFor(FoodDbEntry e) => {
        'name': e.name,
        if (e.category != null) 'category': e.category,
        'cal': e.caloriesPer100g,
        if (e.proteinPer100g != null) 'protein': e.proteinPer100g,
        if (e.carbsPer100g != null) 'carbs': e.carbsPer100g,
        if (e.fatPer100g != null) 'fat': e.fatPer100g,
      };

  FoodDbEntry? _entryFromMetadata(String id, String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final name = json['name'] as String?;
      final cal = json['cal'];
      if (name == null || cal == null) return null;
      return FoodDbEntry(
        id: id,
        name: name,
        category: json['category'] as String?,
        caloriesPer100g: (cal as num).toDouble(),
        proteinPer100g: (json['protein'] as num?)?.toDouble(),
        carbsPer100g: (json['carbs'] as num?)?.toDouble(),
        fatPer100g: (json['fat'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  void _publish(void Function(IndexProgress)? onProgress) {
    _progressController.add(_progress);
    onProgress?.call(_progress);
  }

  /// Fast-path index build from pre-computed vectors.
  ///
  /// Skips the embedding model entirely — vectors come from [bundleVectors]
  /// (loaded via [VectorBundleService.loadVectors]). Only HNSW insertion +
  /// food-DB metadata lookups are performed, which takes seconds vs 10+ min.
  Future<void> buildIndexFromBundle({
    required List<({String id, List<double> vector})> bundleVectors,
    void Function(IndexProgress)? onProgress,
  }) async {
    if (_isIndexing) return;
    if (!_isVectorStoreInitialized) await init();
    _isIndexing = true;
    try {
      final total = bundleVectors.length;
      _progress = IndexProgress(indexed: 0, total: total, isComplete: false);
      _publish(onProgress);

      const batchSize = 64;
      var indexed = 0;
      while (indexed < bundleVectors.length) {
        final end = (indexed + batchSize).clamp(0, bundleVectors.length);
        final batch = bundleVectors.sublist(indexed, end);
        final ids = batch.map((e) => e.id).toList();
        final entries = await _foodDb.getByIds(ids);
        final byId = {for (final e in entries) e.id: e};

        for (final item in batch) {
          final entry = byId[item.id];
          if (entry == null) continue;
          await _plugin.addDocumentWithEmbedding(
            id: entry.id,
            content: _documentTextFor(entry),
            embedding: item.vector,
            metadata: jsonEncode(_metadataFor(entry)),
          );
        }

        indexed = end;
        _progress = _progress.copyWith(indexed: indexed, total: total);
        await _storage.saveFoodIndexProgress(_progress);
        _publish(onProgress);
      }

      _progress = _progress.copyWith(
        isComplete: true,
        completedAt: DateTime.now(),
      );
      await _storage.saveFoodIndexProgress(_progress);
      _publish(onProgress);
    } finally {
      _isIndexing = false;
    }
  }

  /// Developer tool: run a full [buildIndex] pass AND simultaneously write
  /// every generated vector to [exportTo] as a reusable bundle.
  ///
  /// Upload the resulting file to GitHub Releases so users can skip the
  /// slow on-device build in future installs.
  Future<void> buildAndExportBundle({
    required VectorBundleService exportTo,
    int batchSize = 64,
    void Function(IndexProgress)? onProgress,
  }) async {
    if (_isIndexing) return;
    if (!_isVectorStoreInitialized) await init();
    if (!_embedder.isReady) {
      debugPrint('FoodSemanticSearchService: embedder not ready; skip export');
      return;
    }
    _isIndexing = true;
    final allVectors = <({String id, List<double> vector})>[];
    try {
      final total = await _foodDb.totalRowCount();
      _progress = IndexProgress(indexed: 0, total: total, isComplete: false);
      _publish(onProgress);

      String? cursor;
      while (true) {
        final page = await _foodDb.getAllForIndex(
          afterId: cursor,
          limit: batchSize,
        );
        if (page.isEmpty) break;

        final texts = page.map(_documentTextFor).toList();
        final List<List<double>> vectors;
        try {
          vectors = await _embedder.embedBatch(texts);
        } catch (e) {
          debugPrint(
              'FoodSemanticSearchService.buildAndExportBundle: embed failed: $e');
          break;
        }
        if (vectors.length != page.length) break;

        for (var i = 0; i < page.length; i++) {
          final entry = page[i];
          allVectors.add((id: entry.id, vector: vectors[i]));
          await _plugin.addDocumentWithEmbedding(
            id: entry.id,
            content: texts[i],
            embedding: vectors[i],
            metadata: jsonEncode(_metadataFor(entry)),
          );
        }

        cursor = page.last.id;
        _progress = _progress.copyWith(
          indexed: _progress.indexed + page.length,
          lastFoodId: cursor,
          total: total,
        );
        await _storage.saveFoodIndexProgress(_progress);
        _publish(onProgress);
        if (page.length < batchSize) break;
      }

      await exportTo.writeVectors(allVectors);

      _progress = _progress.copyWith(
        isComplete: true,
        completedAt: DateTime.now(),
      );
      await _storage.saveFoodIndexProgress(_progress);
      _publish(onProgress);
    } finally {
      _isIndexing = false;
    }
  }

  Future<void> dispose() async {
    await _progressController.close();
  }
}
