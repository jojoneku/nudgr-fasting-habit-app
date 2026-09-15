import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/services/backup_service.dart';

/// In-memory stand-in for the platform keystore.
class _MemoryKeyStore implements BackupKeyStore {
  String? value;
  int writeCount = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async {
    value = v;
    writeCount++;
  }

  @override
  Future<void> delete() async => value = null;
}

/// A keystore that is present but broken, e.g. a device where the Keystore
/// call throws. The service must degrade, never crash the caller.
class _BrokenKeyStore implements BackupKeyStore {
  @override
  Future<String?> read() async => throw Exception('keystore unavailable');

  @override
  Future<void> write(String v) async => throw Exception('keystore unavailable');

  @override
  Future<void> delete() async => throw Exception('keystore unavailable');
}

void main() {
  late Directory dir;
  late _MemoryKeyStore keys;
  late BackupService service;

  const userId = 'user-abc';
  final payload = <String, dynamic>{
    'weightLog': '[{"kg":71.4,"date":"2026-09-01"}]',
    'finance_transactions': '[{"amount":1250.00,"note":"groceries"}]',
  };

  BackupService serviceWith(BackupKeyStore store) => BackupService(
        keyStore: store,
        documentsDirectory: () async => dir,
        now: () => DateTime.utc(2026, 9, 12),
      );

  File backupFile() => File('${dir.path}/backup.json');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nudgr_backup_test');
    keys = _MemoryKeyStore();
    service = serviceWith(keys);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('round trip', () {
    test('write then read returns the same data', () async {
      await service.writeBackup(userId, payload);
      expect(await service.readBackup(userId), payload);
    });

    test('a second write reuses the data key rather than minting a new one',
        () async {
      // A fresh key per write would make every previous backup unreadable.
      await service.writeBackup(userId, payload);
      await service.writeBackup(userId, payload);
      expect(keys.writeCount, 1);
      expect(await service.readBackup(userId), payload);
    });

    test('a different user gets nothing back', () async {
      await service.writeBackup(userId, payload);
      expect(await service.readBackup('someone-else'), isNull);
    });
  });

  group('what actually lands on disk', () {
    test('is ciphertext, not the user data', () async {
      await service.writeBackup(userId, payload);
      final raw = await backupFile().readAsString();

      // The point of the whole change: none of this may be legible in the file.
      expect(raw, isNot(contains('groceries')));
      expect(raw, isNot(contains('71.4')));
      expect(raw, isNot(contains('weightLog')));
      expect(raw, isNot(contains(userId)));

      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      expect(envelope['version'], 2);
      expect(envelope['payload'], isA<String>());
      expect(envelope.containsKey('data'), isFalse);
    });

    test('the envelope is tamper-evident', () async {
      // AES-GCM authenticates. Flipping bytes must fail the MAC and surface as
      // "no backup", not as silently corrupted data handed to the restore path.
      await service.writeBackup(userId, payload);
      final envelope =
          jsonDecode(await backupFile().readAsString()) as Map<String, dynamic>;
      final bytes = base64Decode(envelope['payload'] as String);
      bytes[bytes.length - 1] ^= 0xFF;
      envelope['payload'] = base64Encode(bytes);
      await backupFile().writeAsString(jsonEncode(envelope));

      expect(await service.readBackup(userId), isNull);
    });
  });

  group('backward compatibility', () {
    test('a v1 plaintext backup from an older build still restores', () async {
      // Users upgrading carry one of these. Refusing it would throw away the
      // safety net at exactly the moment it might be needed.
      await backupFile().writeAsString(jsonEncode({
        'version': 1,
        'userId': userId,
        'savedAt': '2026-08-01T00:00:00.000Z',
        'data': payload,
      }));

      expect(await service.readBackup(userId), payload);
    });

    test('the next write upgrades it to an encrypted envelope', () async {
      await backupFile().writeAsString(jsonEncode({
        'version': 1,
        'userId': userId,
        'savedAt': '2026-08-01T00:00:00.000Z',
        'data': payload,
      }));

      await service.writeBackup(userId, payload);
      final raw = await backupFile().readAsString();
      expect((jsonDecode(raw) as Map<String, dynamic>)['version'], 2);
      expect(raw, isNot(contains('groceries')));
    });
  });

  group('degraded states', () {
    test('a lost data key reads as "no backup" instead of throwing', () async {
      await service.writeBackup(userId, payload);
      keys.value = null; // keystore wiped out from under us

      expect(await service.readBackup(userId), isNull);
    });

    test('a wrong data key reads as "no backup"', () async {
      await service.writeBackup(userId, payload);
      keys.value = base64Encode(List<int>.filled(32, 7));

      expect(await service.readBackup(userId), isNull);
    });

    test('an unusable keystore skips the write rather than writing plaintext',
        () async {
      // The one thing this must never do is fall back to writing the clear
      // text when the keystore misbehaves.
      final broken = serviceWith(_BrokenKeyStore());
      await broken.writeBackup(userId, payload);

      expect(await backupFile().exists(), isFalse);
    });

    test('empty data never overwrites a good backup', () async {
      await service.writeBackup(userId, payload);
      await service.writeBackup(userId, <String, dynamic>{});

      expect(await service.readBackup(userId), payload);
    });

    test('reading when no file exists returns null', () async {
      expect(await service.readBackup(userId), isNull);
    });
  });

  group('deleteBackup', () {
    test('removes the file and the data key', () async {
      await service.writeBackup(userId, payload);
      expect(await backupFile().exists(), isTrue);
      expect(keys.value, isNotNull);

      await service.deleteBackup();

      expect(await backupFile().exists(), isFalse);
      expect(keys.value, isNull);
    });

    test('is safe to call when there is nothing to delete', () async {
      await service.deleteBackup();
      expect(await backupFile().exists(), isFalse);
    });
  });
}
