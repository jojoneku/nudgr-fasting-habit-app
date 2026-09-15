import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Thrown when a downloaded APK is not the one the manifest describes, or the
/// manifest carries no hash to compare against.
///
/// Distinct from the generic download failures so the UI can say something
/// truthful: a transport error is worth retrying, a hash mismatch is not. The
/// same bytes will keep producing the same wrong digest, and the retry prompt
/// that fits a dropped connection is actively misleading here.
class ApkIntegrityException implements Exception {
  final String message;

  ApkIntegrityException(this.message);

  @override
  String toString() => 'ApkIntegrityException: $message';
}

class UpdateManifest {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String releaseNotes;
  final DateTime releasedAt;

  /// SHA-256 of the release APK, lowercase hex, as published by CI alongside
  /// [apkUrl].
  ///
  /// Nullable because a manifest is external JSON and the field postdates the
  /// first releases — but [UpdateService] REFUSES to install an APK without
  /// it. That is deliberate. An integrity check that is skipped when the field
  /// is absent is not an integrity check: anyone able to serve a doctored
  /// manifest would just leave the key out. Failing closed costs a broken
  /// update button (and the GitHub release page still works); failing open
  /// costs the user an attacker-chosen APK, handed to the package installer by
  /// an app that holds REQUEST_INSTALL_PACKAGES.
  final String? apkSha256;

  UpdateManifest({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.releasedAt,
    this.apkSha256,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      version: json['version'] as String,
      buildNumber: json['build_number'] as int,
      apkUrl: json['apk_url'] as String,
      releaseNotes: json['release_notes'] as String? ?? '',
      releasedAt: DateTime.parse(json['released_at'] as String),
      apkSha256: (json['apk_sha256'] as String?)?.trim().toLowerCase(),
    );
  }
}

class UpdateService {
  final String manifestUrl;

  UpdateService({required this.manifestUrl});

  /// Whether this platform can download + hand the APK to the OS package
  /// installer. Everywhere else (web, desktop) callers fall back to opening
  /// the release URL in a browser.
  bool get supportsInAppInstall =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<UpdateManifest?> fetchLatestManifest() async {
    try {
      final bustUrl = Uri.parse(manifestUrl).replace(
        queryParameters: {
          '_t': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final response = await http.get(bustUrl, headers: {
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Timeout fetching manifest'),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return UpdateManifest.fromJson(json);
      }
      debugPrint('Failed to fetch manifest: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('Error fetching manifest: $e');
      return null;
    }
  }

  /// Directory the downloaded APKs live in. External app-specific storage is
  /// readable by the package installer (via the plugin's FileProvider); the
  /// documents dir is the fallback for devices where it's unavailable.
  Future<Directory> _updatesDir() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _apkFileName(UpdateManifest manifest) =>
      'nudgr-${manifest.version}-${manifest.buildNumber}.apk';

  /// Returns the fully-downloaded APK for [manifest] if a previous attempt
  /// already cached it, deleting any stale APKs from older versions so the
  /// updates dir never holds more than one file.
  Future<File?> cachedApk(UpdateManifest manifest) async {
    try {
      final dir = await _updatesDir();
      final wanted = _apkFileName(manifest);
      File? match;
      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.endsWith('.apk')) continue;
        if (entry.uri.pathSegments.last == wanted) {
          match = entry;
        } else {
          try {
            await entry.delete();
          } catch (_) {/* best-effort cleanup */}
        }
      }
      if (match == null) return null;
      // A cached APK is a file sitting in external app-specific storage
      // between the download and the install. Re-verify it: skipping the check
      // here would mean the very first run verifies and every subsequent
      // resume-the-download path does not.
      if (!await _apkMatchesManifest(match, manifest)) {
        debugPrint('UpdateService: cached APK failed its check, discarding');
        try {
          await match.delete();
        } catch (_) {/* best-effort */}
        return null;
      }
      return match;
    } catch (e) {
      debugPrint('UpdateService: cachedApk failed: $e');
      return null;
    }
  }

  /// Streams [file] through SHA-256 and compares it to
  /// [UpdateManifest.apkSha256]. Returns false when the manifest carries no
  /// hash — see the field doc for why that is a refusal and not a pass.
  Future<bool> _apkMatchesManifest(File file, UpdateManifest manifest) async {
    final expected = manifest.apkSha256;
    if (expected == null || expected.isEmpty) {
      debugPrint('UpdateService: manifest has no apk_sha256; refusing the APK');
      return false;
    }
    try {
      final actual = await _sha256OfFile(file);
      if (actual != expected) {
        debugPrint('UpdateService: APK hash mismatch '
            '(expected $expected, got $actual)');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('UpdateService: hashing the APK failed: $e');
      return false;
    }
  }

  /// SHA-256 of [file] as lowercase hex, hashed in chunks.
  ///
  /// Chunked rather than `sha256.convert(await file.readAsBytes())` because an
  /// APK is tens of megabytes and reading it whole is an allocation this can
  /// avoid on exactly the low-memory devices most likely to be sideloading.
  Future<String> _sha256OfFile(File file) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.value.toString();
  }

  /// Downloads the APK for [manifest], streaming progress via [onProgress]
  /// (received bytes, total bytes — total is 0 when the server doesn't send a
  /// length). Deletes the partial file and rethrows on any failure.
  Future<File> downloadApk(
    UpdateManifest manifest, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await _updatesDir();
    final file = File('${dir.path}/${_apkFileName(manifest)}');
    final client = http.Client();
    IOSink? sink;
    try {
      // GitHub release-asset URLs 302-redirect to a signed CDN URL; the http
      // client follows that transparently — the browser hand-off this
      // replaces is where those downloads used to die.
      final request = http.Request('GET', Uri.parse(manifest.apkUrl));
      final response = await client.send(request).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Timeout starting download'),
          );
      if (response.statusCode != 200) {
        throw Exception('Download failed (HTTP ${response.statusCode})');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      // Hashed on the way through rather than by re-reading the finished file:
      // the bytes are already in hand, and it keeps the check on the exact
      // stream that was written instead of whatever is on disk afterwards.
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hasher.close();
      if (total > 0 && received < total) {
        throw Exception('Download incomplete ($received of $total bytes)');
      }

      // Integrity gate. TLS to github.com and Android's own signature check on
      // upgrade both already stand between a user and a hostile APK; this
      // closes the gap they leave, which is a release asset that is not the
      // one CI built. Throwing (rather than returning a flag) reuses the
      // catch below, so a failed APK is deleted and never reaches the
      // installer.
      final expected = manifest.apkSha256;
      if (expected == null || expected.isEmpty) {
        throw ApkIntegrityException(
            'Update manifest is missing apk_sha256; refusing to install an '
            'unverified APK.');
      }
      final actual = digestSink.value.toString();
      if (actual != expected) {
        throw ApkIntegrityException(
            'Downloaded APK failed its integrity check (expected $expected, '
            'got $actual). The file was discarded.');
      }
      return file;
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Hands the downloaded APK to the Android package installer.
  /// Returns null on success, or a user-facing error message.
  Future<String?> openApkInstaller(String apkPath) async {
    try {
      final result = await OpenFilex.open(apkPath);
      if (result.type == ResultType.done) return null;
      return result.message;
    } catch (e) {
      return e.toString();
    }
  }

  static int _parseVersion(String version) {
    final parts = version.split('.');
    if (parts.length >= 3) {
      try {
        final major = int.parse(parts[0]);
        final minor = int.parse(parts[1]);
        final patch = int.parse(parts[2]);
        return major * 10000 + minor * 100 + patch;
      } catch (e) {
        debugPrint('Error parsing version: $e');
        return 0;
      }
    }
    return 0;
  }

  /// Returns true if [remoteVersion] is newer than [localVersion]
  static bool isUpdateAvailable(String localVersion, String remoteVersion) {
    final localParsed = _parseVersion(localVersion);
    final remoteParsed = _parseVersion(remoteVersion);
    return remoteParsed > localParsed;
  }
}

/// Collects the single [Digest] that `sha256.startChunkedConversion` emits on
/// close.
///
/// `package:convert`'s AccumulatorSink does this too, but convert is only a
/// transitive dependency here — four lines beat promoting a package to a
/// direct one for one callback.
class _DigestSink implements Sink<Digest> {
  late final Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
