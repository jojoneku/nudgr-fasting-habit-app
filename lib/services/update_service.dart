import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  Future<UpdateManifest?> fetchLatestManifest() async {
    try {
      final response = await http.get(Uri.parse(manifestUrl)).timeout(
            const Duration(seconds: 10),
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
