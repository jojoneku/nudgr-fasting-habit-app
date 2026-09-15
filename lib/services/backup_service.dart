import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// The slice of secure storage [BackupService] needs: one key, three verbs.
///
/// Narrower than handing the service a [FlutterSecureStorage] so a test can
/// substitute an in-memory store without matching that class's (long, and
/// version-dependent) method signatures.
abstract class BackupKeyStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Default [BackupKeyStore]: the platform keystore, via
/// `flutter_secure_storage` (Keychain on iOS, Keystore-backed
/// EncryptedSharedPreferences on Android).
class SecureBackupKeyStore implements BackupKeyStore {
  const SecureBackupKeyStore([this._storage = _defaultStorage]);

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: BackupService.dekKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: BackupService.dekKey, value: value);

  @override
  Future<void> delete() => _storage.delete(key: BackupService.dekKey);
}

/// On-device JSON backup of all local user data (Plan 053 Phase 0.5).
///
/// Writes a `backup.json` to the app documents directory that the sign-out /
/// detach path never touches, so local progress can be recovered even if the
/// SharedPreferences store is ever cleared while the app is installed. This is
/// the device-local safety net; the durable cross-device backup is the
/// immutable cloud snapshot (Phase 3.5).
///
/// **Encrypted at rest** since `docs/data_security_spec.md` Phase 0. The file
/// is a full plaintext dump of everything the app knows — weight and body
/// measurements, meal logs, account balances, transactions, debts — sitting in
/// the documents directory. AES-256-GCM with a data key in
/// `flutter_secure_storage` (Keychain / Android Keystore backed) closes that.
///
/// Backward compatible on read: a v1 plaintext file written by an older build
/// still restores. It is not rewritten in place on read (a read that silently
/// writes is a worse contract than a stale file) — the next [writeBackup]
/// replaces it with a v2 encrypted one, and those run whenever data changes.
///
/// Mobile-only: the browser has no filesystem, so every method is a safe no-op
/// on web (where the equivalent is the manual export/import in Plan 044).
class BackupService {
  /// Plaintext envelope written by builds before Phase 0. Still readable.
  static const int _schemaVersionPlaintext = 1;

  /// AES-256-GCM envelope.
  static const int _schemaVersionEncrypted = 2;

  static const String _fileName = 'backup.json';

  /// Secure-storage key holding the base64 AES-256 data key (DEK).
  ///
  /// The DEK survives a SharedPreferences wipe, which is the exact event this
  /// backup exists to survive, so encrypting with it does not undermine the
  /// file's purpose. A full keystore wipe (factory reset, some restore-to-new-
  /// device paths) does invalidate the local backup — at which point the cloud
  /// snapshot is the recovery path, as it already was.
  static const String dekKey = 'backup.dek.v1';

  static final AesGcm _algorithm = AesGcm.with256bits();

  /// Injectable timestamp so callers/tests control `savedAt` (the app already
  /// avoids ambient clocks in pure code paths).
  final DateTime Function() _now;

  final BackupKeyStore _keyStore;

  /// Where `backup.json` lives. Injected so a test can point at a temp dir
  /// instead of standing up the path_provider platform channel.
  final Future<Directory> Function() _documentsDirectory;

  BackupService({
    DateTime Function()? now,
    BackupKeyStore? keyStore,
    Future<Directory> Function()? documentsDirectory,
  })  : _now = now ?? DateTime.now,
        _keyStore = keyStore ?? const SecureBackupKeyStore(),
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await _documentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (e) {
      debugPrint('BackupService: could not resolve documents dir: $e');
      return null;
    }
  }

  // ── Key handling ───────────────────────────────────────────────────────────

  /// Returns the data key, generating and storing one on first use.
  ///
  /// Returns null if secure storage is unusable. Callers treat that as "cannot
  /// encrypt" and skip the write rather than falling back to plaintext — a
  /// fallback that writes the clear text whenever the keystore is unhappy is
  /// the same exposure with extra steps.
  Future<SecretKey?> _loadOrCreateKey() async {
    try {
      final existing = await _keyStore.read();
      if (existing != null && existing.isNotEmpty) {
        return SecretKey(base64Decode(existing));
      }
      final created = await _algorithm.newSecretKey();
      final bytes = await created.extractBytes();
      await _keyStore.write(base64Encode(bytes));
      return created;
    } catch (e) {
      debugPrint('BackupService: could not obtain the data key: $e');
      return null;
    }
  }

  /// Returns the existing data key, or null. Never creates one: a read has
  /// nothing to do with a fresh key, and minting one here would turn "the key
  /// is gone" into "decryption failed" one step later.
  Future<SecretKey?> _loadKey() async {
    try {
      final existing = await _keyStore.read();
      if (existing == null || existing.isEmpty) return null;
      return SecretKey(base64Decode(existing));
    } catch (e) {
      debugPrint('BackupService: could not read the data key: $e');
      return null;
    }
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Writes [data] (from `LocalStorageService.exportUserData`) for [userId].
  /// Never throws — a backup failure must not disrupt the app.
  Future<void> writeBackup(String userId, Map<String, dynamic> data) async {
    if (kIsWeb) return;
    if (data.isEmpty) return; // never overwrite a good backup with nothing
    final file = await _file();
    if (file == null) return;
    try {
      final inner = jsonEncode({
        'version': _schemaVersionPlaintext,
        'userId': userId,
        'savedAt': _now().toUtc().toIso8601String(),
        'data': data,
      });

      final key = await _loadOrCreateKey();
      if (key == null) {
        debugPrint('BackupService: no data key, skipping backup write');
        return;
      }

      final box = await _algorithm.encrypt(
        utf8.encode(inner),
        secretKey: key,
      );
      // concatenation() is nonce || ciphertext || mac, the layout the spec
      // calls for. Using it rather than three separate fields keeps the
      // envelope small and the parsing unambiguous.
      final payload = base64Encode(box.concatenation());

      await file.writeAsString(
        jsonEncode({'version': _schemaVersionEncrypted, 'payload': payload}),
        flush: true,
      );
      debugPrint('BackupService: wrote encrypted backup '
          '(${data.length} keys)');
    } catch (e) {
      debugPrint('BackupService: writeBackup failed: $e');
    }
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Returns the backed-up data map for [userId], or null if there is no
  /// backup, it belongs to a different user, or it can't be read, decrypted or
  /// parsed.
  ///
  /// A decryption failure returns null rather than throwing — the same
  /// contract a parse failure has always had, so callers are unchanged.
  Future<Map<String, dynamic>?> readBackup(String userId) async {
    if (kIsWeb) return null;
    final file = await _file();
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;

      final envelope = decoded['version'] == _schemaVersionEncrypted
          ? await _decryptEnvelope(decoded)
          : decoded;
      if (envelope == null) return null;

      if (envelope['userId'] != userId) return null; // not this user's backup
      final data = envelope['data'];
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('BackupService: readBackup failed: $e');
      return null;
    }
  }

  /// Unwraps a v2 envelope into the v1-shaped map the rest of [readBackup]
  /// already understands. Returns null when it cannot be opened.
  Future<Map<String, dynamic>?> _decryptEnvelope(
    Map<String, dynamic> decoded,
  ) async {
    final payload = decoded['payload'];
    if (payload is! String || payload.isEmpty) return null;

    final key = await _loadKey();
    if (key == null) {
      debugPrint('BackupService: backup is encrypted but the key is gone');
      return null;
    }

    final box = SecretBox.fromConcatenation(
      base64Decode(payload),
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clear = await _algorithm.decrypt(box, secretKey: key);
    final inner = jsonDecode(utf8.decode(clear));
    return inner is Map<String, dynamic> ? inner : null;
  }

  // ── Teardown ───────────────────────────────────────────────────────────────

  /// Removes the backup file and its data key.
  ///
  /// Reserved for an explicit account reset / "delete my data", NOT ordinary
  /// sign-out — sign-out must keep the safety net (see
  /// `LocalStorageService.detachUser` vs `clearUserData` for the same split).
  /// The key goes with the file: leaving a DEK behind for a deleted backup
  /// serves nothing and is one more secret to look after.
  Future<void> deleteBackup() async {
    if (kIsWeb) return;
    final file = await _file();
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('BackupService: deleteBackup failed: $e');
    }
    try {
      await _keyStore.delete();
    } catch (e) {
      debugPrint('BackupService: deleting the data key failed: $e');
    }
  }
}
