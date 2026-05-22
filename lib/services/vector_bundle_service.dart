import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Manages the pre-built food embedding vector bundle.
///
/// The bundle is a compact binary (~49 MB) containing pre-computed 768-dim
/// vectors for every food entry in the bundled DB. Downloading it lets the
/// app skip the 10–15 minute on-device embedding step — vectors are inserted
/// directly into the HNSW index in seconds instead.
///
/// Binary format (little-endian):
///   Header  — magic 'FVEB'(4) | version uint32(4) | count uint32(4) | dims uint32(4)
///   Per entry — id_len uint32(4) | id UTF-8(id_len) | float32 × dims
class VectorBundleService {
  /// URL of the pre-built bundle on GitHub Releases.
  /// Stub until the bundle is built and uploaded via buildAndExportBundle().
  static const String bundleUrl =
      'https://github.com/jojoneku/nudgr-fasting-habit-app'
      '/releases/download/vectors-v1/food_vectors.bin';

  static const String _filename = 'food_vectors.bin';
  static const int _magic = 0x42455646; // 'FVEB' as uint32 LE
  static const int _currentVersion = 1;

  bool _isDownloading = false;
  int _downloadProgress = 0;

  bool get isDownloading => _isDownloading;
  int get downloadProgress => _downloadProgress;

  Future<String> get _filePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}$_filename';
  }

  Future<bool> isDownloaded() async {
    try {
      return File(await _filePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Stream-download the bundle from [bundleUrl], reporting 0–100 progress.
  Future<void> download({void Function(int)? onProgress}) async {
    if (_isDownloading) return;
    _isDownloading = true;
    _downloadProgress = 0;
    final path = await _filePath;
    File? partial;
    try {
      partial = File('$path.part');
      final request = http.Request('GET', Uri.parse(bundleUrl));
      final response = await request.send();
      if (response.statusCode != 200) {
        throw Exception('Bundle download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = partial.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = ((received / total) * 100).round().clamp(0, 100);
          if (pct != _downloadProgress) {
            _downloadProgress = pct;
            onProgress?.call(pct);
          }
        }
      }
      await sink.flush();
      await sink.close();
      await partial.rename(path);
      _downloadProgress = 100;
      onProgress?.call(100);
    } catch (e) {
      await partial?.delete().catchError((_) => File(''));
      debugPrint('VectorBundleService.download failed: $e');
      rethrow;
    } finally {
      _isDownloading = false;
    }
  }

  /// Parse the bundle file and return all (foodId, vector) pairs.
  Future<List<({String id, List<double> vector})>> loadVectors() async {
    final bytes = await File(await _filePath).readAsBytes();
    final data = ByteData.sublistView(bytes);
    var offset = 0;

    final magic = data.getUint32(offset, Endian.little);
    offset += 4;
    if (magic != _magic)
      throw FormatException('Bad bundle magic: 0x${magic.toRadixString(16)}');

    final version = data.getUint32(offset, Endian.little);
    offset += 4;
    if (version != _currentVersion) {
      throw FormatException('Unsupported bundle version: $version');
    }

    final count = data.getUint32(offset, Endian.little);
    offset += 4;
    final dims = data.getUint32(offset, Endian.little);
    offset += 4;

    final results = <({String id, List<double> vector})>[];
    for (var i = 0; i < count; i++) {
      final idLen = data.getUint32(offset, Endian.little);
      offset += 4;
      final id = utf8.decode(bytes.sublist(offset, offset + idLen));
      offset += idLen;
      final vector = List<double>.generate(
        dims,
        (j) => data.getFloat32(offset + j * 4, Endian.little),
        growable: false,
      );
      offset += dims * 4;
      results.add((id: id, vector: vector));
    }
    return results;
  }

  /// Write (foodId, vector) pairs to the bundle file.
  /// Used by [FoodSemanticSearchService.buildAndExportBundle] on a dev device
  /// to generate the bundle before uploading it to GitHub Releases.
  Future<void> writeVectors(
      List<({String id, List<double> vector})> vectors) async {
    if (vectors.isEmpty) return;
    final dims = vectors.first.vector.length;

    // Pre-encode IDs so we know the exact byte sizes up front.
    final encodedIds = vectors.map((v) => utf8.encode(v.id)).toList();
    var totalBytes = 16; // header
    for (final id in encodedIds) {
      totalBytes += 4 + id.length + dims * 4;
    }

    final buffer = ByteData(totalBytes);
    var offset = 0;

    buffer.setUint32(offset, _magic, Endian.little);
    offset += 4;
    buffer.setUint32(offset, _currentVersion, Endian.little);
    offset += 4;
    buffer.setUint32(offset, vectors.length, Endian.little);
    offset += 4;
    buffer.setUint32(offset, dims, Endian.little);
    offset += 4;

    for (var i = 0; i < vectors.length; i++) {
      final idBytes = encodedIds[i];
      buffer.setUint32(offset, idBytes.length, Endian.little);
      offset += 4;
      for (final b in idBytes) {
        buffer.setUint8(offset++, b);
      }
      final vec = vectors[i].vector;
      for (var j = 0; j < dims; j++) {
        buffer.setFloat32(offset, vec[j], Endian.little);
        offset += 4;
      }
    }

    await File(await _filePath).writeAsBytes(buffer.buffer.asUint8List());
  }

  Future<void> delete() async {
    try {
      final file = File(await _filePath);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('VectorBundleService.delete failed: $e');
    }
  }
}
