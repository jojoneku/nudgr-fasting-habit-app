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
  static const _dbFilename = 'food_db_v1.sqlite';

  Database? _db;

  bool get isReady => _db != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      final path = await _resolveDbPath();
      _db = await openDatabase(path, readOnly: true);
    } catch (e) {
      // Asset not bundled or copy failed — search will return empty results.
      debugPrint('FoodDbService: init failed: $e');
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  /// FTS5 prefix search — returns up to 20 matches for [query].
  /// Returns [] when the DB is not initialised or query is blank.
  Future<List<FoodDbEntry>> search(String query) async {
    if (_db == null || query.trim().isEmpty) return [];

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
      // FTS5 not available on this SQLite build — fall back to LIKE
      return _searchLike(query);
    }
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
    final pattern = '%${query.trim()}%';
    final rows = await _db!.query(
      'foods',
      where: 'name LIKE ?',
      whereArgs: [pattern],
      limit: 20,
    );
    return rows.map(FoodDbEntry.fromRow).toList();
  }
}
