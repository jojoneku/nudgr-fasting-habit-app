import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On-device JSON backup of all local user data (Plan 053 Phase 0.5).
///
/// Writes a `backup.json` to the app documents directory that the sign-out /
/// detach path never touches, so local progress can be recovered even if the
/// SharedPreferences store is ever cleared while the app is installed. This is
/// the device-local safety net; the durable cross-device backup is the
/// immutable cloud snapshot (Phase 3.5).
///
/// Mobile-only: the browser has no filesystem, so every method is a safe no-op
/// on web (where the equivalent is the manual export/import in Plan 044).
class BackupService {
  static const int _schemaVersion = 1;
  static const String _fileName = 'backup.json';

  /// Injectable timestamp so callers/tests control `savedAt` (the app already
  /// avoids ambient clocks in pure code paths).
  final DateTime Function() _now;

  BackupService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (e) {
      debugPrint('BackupService: could not resolve documents dir: $e');
      return null;
    }
  }

  /// Writes [data] (from `LocalStorageService.exportUserData`) for [userId].
  /// Never throws — a backup failure must not disrupt the app.
  Future<void> writeBackup(String userId, Map<String, dynamic> data) async {
    if (kIsWeb) return;
    if (data.isEmpty) return; // never overwrite a good backup with nothing
    final file = await _file();
    if (file == null) return;
    try {
      final payload = jsonEncode({
        'version': _schemaVersion,
        'userId': userId,
        'savedAt': _now().toUtc().toIso8601String(),
        'data': data,
      });
      await file.writeAsString(payload, flush: true);
      debugPrint('BackupService: wrote backup (${data.length} keys)');
    } catch (e) {
      debugPrint('BackupService: writeBackup failed: $e');
    }
  }

  /// Returns the backed-up data map for [userId], or null if there is no
  /// backup, it belongs to a different user, or it can't be read/parsed.
  Future<Map<String, dynamic>?> readBackup(String userId) async {
    if (kIsWeb) return null;
    final file = await _file();
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['userId'] != userId) return null; // not this user's backup
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('BackupService: readBackup failed: $e');
      return null;
    }
  }

  /// Removes the backup file (e.g. on an explicit account reset).
  Future<void> deleteBackup() async {
    if (kIsWeb) return;
    final file = await _file();
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('BackupService: deleteBackup failed: $e');
    }
  }
}
