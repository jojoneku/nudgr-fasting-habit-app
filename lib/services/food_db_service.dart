import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/food_db_entry.dart';

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
  static const _dbFilename = 'food_db_v4.sqlite';

  Database? _db;
  bool _fts5Available = false;

  bool get isReady => _db != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      final path = await _resolveDbPath();
      _db = await openDatabase(path, readOnly: true);
      _fts5Available = await _checkFts5();
      debugPrint('FoodDbService: fts5=${_fts5Available}');
    } catch (e) {
      // Asset not bundled or copy failed — search will return empty results.
      debugPrint('FoodDbService: init failed: $e');
    }
  }

  Future<bool> _checkFts5() async {
    try {
      await _db!.rawQuery(
        'SELECT rowid FROM foods_fts WHERE foods_fts MATCH ? LIMIT 1',
        ['test*'],
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

  /// Full-text search with automatic FTS5 → LIKE fallback.
  /// FTS5 availability is detected once at init to avoid per-query exceptions.
  Future<List<FoodDbEntry>> search(String query) async {
    if (_db == null || query.trim().isEmpty) return [];

    if (_fts5Available) {
      final q = '${query.trim().replaceAll('"', '""')}*';
      try {
        final rows = await _db!.rawQuery(
          'SELECT f.id, f.name, f.category, f.cal, f.protein, f.carbs, f.fat '
          'FROM foods f '
          'JOIN foods_fts ON foods_fts.rowid = f.rowid '
          'WHERE foods_fts MATCH ? '
          'LIMIT 20',
          [q],
        );
        return rows.map(FoodDbEntry.fromRow).toList();
      } catch (_) {
        _fts5Available = false;
      }
    }

    return _searchLike(query);
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

  Future<List<FoodDbEntry>> _searchLike(String query) async {
    final term = query.trim().toLowerCase();
    // Two-pass: prefix matches first (index-friendly), then contains matches.
    final prefix = await _db!.rawQuery(
      'SELECT id, name, category, cal, protein, carbs, fat '
      'FROM foods WHERE lower(name) LIKE ? LIMIT 20',
      ['$term%'],
    );
    if (prefix.length >= 20) return prefix.map(FoodDbEntry.fromRow).toList();

    final contains = await _db!.rawQuery(
      'SELECT id, name, category, cal, protein, carbs, fat '
      'FROM foods WHERE lower(name) LIKE ? AND lower(name) NOT LIKE ? LIMIT ?',
      ['%$term%', '$term%', 20 - prefix.length],
    );
    return [...prefix, ...contains].map(FoodDbEntry.fromRow).toList();
  }
}
