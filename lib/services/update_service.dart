import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateManifest {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String releaseNotes;
  final DateTime releasedAt;

  UpdateManifest({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.releasedAt,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      version: json['version'] as String,
      buildNumber: json['build_number'] as int,
      apkUrl: json['apk_url'] as String,
      releaseNotes: json['release_notes'] as String? ?? '',
      releasedAt: DateTime.parse(json['released_at'] as String),
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
      return match;
    } catch (e) {
      debugPrint('UpdateService: cachedApk failed: $e');
      return null;
    }
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
      sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (total > 0 && received < total) {
        throw Exception('Download incomplete ($received of $total bytes)');
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
      final result = await OpenFile.open(apkPath);
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
