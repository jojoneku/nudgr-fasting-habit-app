import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persists food-photo thumbnails as JPEG files in the app documents directory
/// and resolves them back for display (Plan 029 §0.4).
///
/// Thumbnails are stored as files — NOT inlined as base64 on the chat message —
/// because chat messages are re-serialised into a single SharedPreferences blob
/// on every write; inline thumbnails would re-encode megabytes on each save.
///
/// The stored reference is a path RELATIVE to the documents directory (e.g.
/// `food_photos/<id>.jpg`) so it survives the app sandbox path changing across
/// reinstalls. Injected into [NutritionPresenter] for testability.
class FoodPhotoStore {
  FoodPhotoStore();

  static const _subDir = 'food_photos';

  Future<Directory> _ensureDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_subDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Write [jpegBytes] as `<id>.jpg`; returns the docs-relative path to store
  /// on the chat message.
  Future<String> saveThumbnail(Uint8List jpegBytes, String id) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/$id.jpg');
    await file.writeAsBytes(jpegBytes, flush: true);
    return '$_subDir/$id.jpg';
  }

  /// Resolve a docs-relative [relativePath] to an absolute path, or null if the
  /// file no longer exists (e.g. cleared on reinstall).
  Future<String?> absolutePath(String relativePath) async {
    final docs = await getApplicationDocumentsDirectory();
    final abs = '${docs.path}/$relativePath';
    return await File(abs).exists() ? abs : null;
  }

  /// Delete the thumbnail file for [relativePath]. Best-effort; never throws.
  Future<void> delete(String relativePath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File('${docs.path}/$relativePath');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // A leaked thumbnail is harmless; swallow IO errors.
    }
  }
}
