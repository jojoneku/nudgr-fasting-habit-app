import '../models/food_db_entry.dart';

/// Stub implementation — real SQLite integration tracked in plan 009.
/// Returns empty results until the food DB asset is bundled.
/// Interface is final; swap the body of each method when plan 009 lands.
class FoodDbService {
  bool _initialized = false;

  Future<void> init() async {
    // TODO (plan 009): copy bundled asset → writable path, open sqflite DB
    _initialized = true;
  }

  Future<List<FoodDbEntry>> search(String query) async {
    if (!_initialized || query.trim().isEmpty) return [];
    // TODO (plan 009): FTS5 MATCH query against SQLite DB
    return [];
  }

  Future<FoodDbEntry?> getById(String id) async {
    if (!_initialized) return null;
    // TODO (plan 009): SELECT from SQLite DB by ID
    return null;
  }

  Future<void> close() async {
    // TODO (plan 009): close sqflite DB
    _initialized = false;
  }

  bool get isAvailable => _initialized;
}
