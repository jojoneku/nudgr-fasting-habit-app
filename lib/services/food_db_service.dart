import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/food_db_entry.dart';
import '../utils/food_fuzzy.dart';

/// Wraps the bundled SQLite food database (assets/food_db.sqlite).
///
/// On first launch, copies the asset to the app documents directory so
/// sqflite can open it (Flutter assets are read-only and not directly
/// openable by sqflite on all platforms).
///
/// Subsequent launches skip the copy — versioned filename ensures a
/// schema bump triggers a fresh copy automatically.
class FoodDbService {
  static const _assetPath = 'assets/food_db.sqlite';
  static const _dbFilename = 'food_db_v9.sqlite';

  Database? _db;
  bool _fts5Available = false;

  bool get isReady => _db != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      final path = await _resolveDbPath();
      _db = await openDatabase(path, readOnly: true);
      _fts5Available = await _checkFts5();
      debugPrint('FoodDbService: fts5=$_fts5Available');
    } catch (e) {
      // Asset not bundled or copy failed — search will return empty results.
      debugPrint('FoodDbService: init failed: $e');
    }
  }

  Future<bool> _checkFts5() async {
    try {
      await _db!.rawQuery(
        'SELECT rowid FROM foods_fts WHERE foods_fts MATCH ? LIMIT 1',
        ['"abc"'],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  /// Substring-tolerant full-text search over the trigram-indexed `name_norm`
  /// column. Folds Pinoy spelling variants (pancit↔pansit, ñ→n) and ignores
  /// spacing/punctuation so "bearbrand" and "Bear Brand" both match.
  ///
  /// Pipeline (resolves Plan 022/023/024):
  ///   1. **Trigram FTS5** with per-word + dense-form OR query — handles
  ///      spacing/punctuation differences and Pinoy variants via the
  ///      normalized index.
  ///   2. **Damerau–Levenshtein rerank** when trigram returns empty — catches
  ///      one-edit typos like "chiken→chicken" that trigram can't (different
  ///      sequence of trigrams).
  ///   3. **LIKE** as the very last fallback when FTS5 isn't available.
  Future<List<FoodDbEntry>> search(String query) async {
    if (_db == null || query.trim().isEmpty) return [];

    final dense = SearchNormalize.dense(query);
    if (dense.length < 3) return [];

    if (_fts5Available) {
      final terms = <String>{
        ...SearchNormalize.tokens(query),
        dense,
      }.where((t) => t.length >= 3).toList();

      if (terms.isNotEmpty) {
        final match =
            terms.map((t) => '"${t.replaceAll('"', '""')}"').join(' OR ');
        try {
          final rows = await _db!.rawQuery(
            'SELECT f.id, f.name, f.category, f.cal, f.protein, f.carbs, f.fat '
            'FROM foods f '
            'JOIN foods_fts ON foods_fts.rowid = f.rowid '
            'WHERE foods_fts MATCH ? '
            'ORDER BY rank '
            'LIMIT 20',
            [match],
          );
          if (rows.isNotEmpty) return rows.map(FoodDbEntry.fromRow).toList();
        } catch (e) {
          debugPrint('FoodDbService: FTS5 query failed, falling back: $e');
          _fts5Available = false;
        }
      }
    }

    // Pass 2: trigram missed — try edit-distance rerank for 1-edit typos
    // (chiken→chicken, brocoli→broccoli) that trigram can't catch because
    // the substrings don't overlap. Seeded on the longest token to keep
    // the candidate slice small.
    final tokens = SearchNormalize.tokens(query);
    final fuzzy = await _fuzzyRerank(tokens);
    if (fuzzy.isNotEmpty) return fuzzy;

    return _searchLike(dense);
  }

  /// Damerau–Levenshtein fallback. Pulls a candidate slice via a 3-char
  /// prefix LIKE on the longest query token, then reranks in Dart by edit
  /// distance against the entry's display name. Bounded at 200 candidates
  /// so even a hot query stays under ~5ms.
  Future<List<FoodDbEntry>> _fuzzyRerank(List<String> tokens) async {
    if (tokens.isEmpty) return const [];
    final seed =
        tokens.reduce((a, b) => a.length >= b.length ? a : b).toLowerCase();
    if (seed.length < 3) return const [];
    final prefix = seed.substring(0, 3);

    final rows = await _db!.rawQuery(
      'SELECT id, name, category, cal, protein, carbs, fat '
      'FROM foods WHERE lower(name) LIKE ? LIMIT 200',
      ['%$prefix%'],
    );
    if (rows.isEmpty) return const [];
    final candidates = rows.map(FoodDbEntry.fromRow).toList(growable: false);
    final query = tokens.join(' ');
    return rankByEditDistance<FoodDbEntry>(
      query,
      candidates,
      extractName: (e) => e.name,
      limit: 20,
    );
  }

  /// Exact lookup by USDA FDC id.
  Future<FoodDbEntry?> getById(String id) async {
    if (_db == null) return null;
    final rows = await _db!.query(
      'foods',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : FoodDbEntry.fromRow(rows.first);
  }

  /// Total row count — used by the index builder to size progress bars.
  Future<int> totalRowCount() async {
    if (_db == null) return 0;
    final rows = await _db!.rawQuery('SELECT COUNT(*) AS c FROM foods');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Paged iteration for the embedding index builder. Returns up to [limit]
  /// rows whose id sorts after [afterId] (or from the start when null).
  ///
  /// Order is by id (string), which matches the natural order of the food DB
  /// asset and gives a stable resumable cursor.
  Future<List<FoodDbEntry>> getAllForIndex({
    String? afterId,
    int limit = 500,
  }) async {
    if (_db == null) return const [];
    final rows = await _db!.rawQuery(
      'SELECT id, name, category, cal, protein, carbs, fat '
      'FROM foods '
      '${afterId != null ? "WHERE id > ?" : ""} '
      'ORDER BY id ASC LIMIT ?',
      afterId != null ? [afterId, limit] : [limit],
    );
    return rows.map(FoodDbEntry.fromRow).toList();
  }

  /// Lookup a batch of ids in one query — used to hydrate semantic search hits
  /// when the metadata round-trip isn't trusted.
  Future<List<FoodDbEntry>> getByIds(List<String> ids) async {
    if (_db == null || ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _db!.rawQuery(
      'SELECT id, name, category, cal, protein, carbs, fat '
      'FROM foods WHERE id IN ($placeholders)',
      ids,
    );
    return rows.map(FoodDbEntry.fromRow).toList();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<String> _resolveDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$_dbFilename';

    if (!File(path).existsSync()) {
      final data = await rootBundle.load(_assetPath);
      await File(path).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    return path;
  }

  Future<List<FoodDbEntry>> _searchLike(String dense) async {
    final prefix = await _db!.rawQuery(
      'SELECT id, name, category, cal, protein, carbs, fat '
      'FROM foods WHERE name_norm LIKE ? LIMIT 20',
      ['$dense%'],
    );
    if (prefix.length >= 20) return prefix.map(FoodDbEntry.fromRow).toList();

    final contains = await _db!.rawQuery(
      'SELECT id, name, category, cal, protein, carbs, fat '
      'FROM foods WHERE name_norm LIKE ? AND name_norm NOT LIKE ? LIMIT ?',
      ['%$dense%', '$dense%', 20 - prefix.length],
    );
    return [...prefix, ...contains].map(FoodDbEntry.fromRow).toList();
  }
}

/// Mirrored helpers for normalizing food names + queries to a comparable form.
/// Kept in sync with `scripts/migrate_food_db_v8.py::normalize_for_search` and
/// the import scripts. Anything that touches `name_norm` MUST go through here.
class SearchNormalize {
  SearchNormalize._();

  static final _pancitRe = RegExp(r'\bpancit\b');
  static final _nonAlphanumRe = RegExp(r'[^a-z0-9]+');
  static final _wsRe = RegExp(r'\s+');

  /// Lowercase, fold Pinoy variants, strip ALL non-alphanumeric (incl spaces).
  ///   "Bear Brand (Powder)"   → "bearbrandpowder"
  ///   "Pancit Canton"          → "pansitcanton"
  ///   "Oats, Rolled, Dry"      → "oatsrolleddry"
  static String dense(String input) {
    var s = input.toLowerCase().replaceAll('ñ', 'n');
    s = s.replaceAll(_pancitRe, 'pansit');
    return s.replaceAll(_nonAlphanumRe, '');
  }

  /// Split [input] on whitespace (after lowering + Pinoy fold), strip
  /// punctuation per token, drop tokens shorter than 3 chars (the trigram
  /// tokenizer can't index them so they're noise in MATCH).
  static List<String> tokens(String input) {
    var s = input.toLowerCase().replaceAll('ñ', 'n');
    s = s.replaceAll(_pancitRe, 'pansit');
    return s
        .split(_wsRe)
        .map((w) => w.replaceAll(_nonAlphanumRe, ''))
        .where((w) => w.length >= 3)
        .toList();
  }

  /// Whole-word tokens for the lexical confidence bonus (≥3 chars, alnum-only).
  /// Used to check that every query word appears as a discrete word in the
  /// matched entry's name — substring matches like "red" inside "layered"
  /// don't count, which prevents the Sapin-Sapin/Red Rice false positive.
  static Set<String> wordTokens(String input) {
    return RegExp(r'[a-z0-9]+')
        .allMatches(input.toLowerCase())
        .map((m) => m.group(0)!)
        .where((w) => w.length >= 3)
        .toSet();
  }
}
