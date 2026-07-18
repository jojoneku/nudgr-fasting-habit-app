import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/presenters/update_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

UpdateManifest _manifest(String version) => UpdateManifest(
      version: version,
      buildNumber: 42,
      apkUrl: 'https://example.com/app-release.apk',
      releaseNotes: 'notes',
      releasedAt: DateTime.utc(2026, 7, 1),
    );

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService() : super(manifestUrl: 'https://example.com/manifest');

  UpdateManifest? manifest;
  File? cached;
  bool supports = true;
  bool failDownload = false;
  String? openedPath;
  String? installError;

  @override
  bool get supportsInAppInstall => supports;

  @override
  Future<UpdateManifest?> fetchLatestManifest() async => manifest;

  @override
  Future<File?> cachedApk(UpdateManifest manifest) async => cached;

  @override
  Future<File> downloadApk(
    UpdateManifest manifest, {
    void Function(int received, int total)? onProgress,
  }) async {
    onProgress?.call(25, 100);
    onProgress?.call(100, 100);
    if (failDownload) throw Exception('network down');
    return File('/updates/nudgr-${manifest.version}-42.apk');
  }

  @override
  Future<String?> openApkInstaller(String apkPath) async {
    openedPath = apkPath;
    return installError;
  }
}

void main() {
  late _FakeUpdateService service;
  late UpdatePresenter presenter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakeUpdateService();
    presenter = UpdatePresenter(
      updateService: service,
      storage: LocalStorageService(),
      currentVersion: '1.1.15',
    );
  });

  group('checkForUpdates', () {
    test('newer manifest → available', () async {
      service.manifest = _manifest('1.2.0');
      await presenter.checkForUpdates();
      expect(presenter.state, UpdateFlowState.available);
      expect(presenter.updateAvailable, isTrue);
    });

    test('same version → idle, no update', () async {
      service.manifest = _manifest('1.1.15');
      await presenter.checkForUpdates();
      expect(presenter.state, UpdateFlowState.idle);
      expect(presenter.updateAvailable, isFalse);
    });

    test('manifest fetch failure → idle, no update', () async {
      service.manifest = null;
      await presenter.checkForUpdates();
      expect(presenter.state, UpdateFlowState.idle);
      expect(presenter.updateAvailable, isFalse);
    });

    test('already-downloaded APK skips straight to readyToInstall', () async {
      service.manifest = _manifest('1.2.0');
      service.cached = File('/updates/nudgr-1.2.0-42.apk');
      await presenter.checkForUpdates();
      expect(presenter.state, UpdateFlowState.readyToInstall);
    });

    test('re-check never clobbers a pending install', () async {
      service.manifest = _manifest('1.2.0');
      service.cached = File('/updates/nudgr-1.2.0-42.apk');
      await presenter.checkForUpdates();
      service.cached = null;
      await presenter.checkForUpdates(); // e.g. app resume
      expect(presenter.state, UpdateFlowState.readyToInstall);
    });
  });

  group('downloadUpdate', () {
    setUp(() async {
      service.manifest = _manifest('1.2.0');
      await presenter.checkForUpdates();
    });

    test('success → progress reported → readyToInstall', () async {
      await presenter.downloadUpdate();
      expect(presenter.state, UpdateFlowState.readyToInstall);
      expect(presenter.downloadProgress, 1.0);
    });

    test('failure → error state with message, then retry succeeds', () async {
      service.failDownload = true;
      await presenter.downloadUpdate();
      expect(presenter.state, UpdateFlowState.error);
      expect(presenter.errorMessage, isNotNull);

      service.failDownload = false;
      await presenter.downloadUpdate();
      expect(presenter.state, UpdateFlowState.readyToInstall);
    });

    test('no-op on unsupported platforms', () async {
      service.supports = false;
      await presenter.downloadUpdate();
      expect(presenter.state, UpdateFlowState.available);
    });
  });

  group('installUpdate', () {
    test('routes the downloaded APK path to the installer', () async {
      service.manifest = _manifest('1.2.0');
      await presenter.checkForUpdates();
      await presenter.downloadUpdate();

      final error = await presenter.installUpdate();
      expect(error, isNull);
      expect(service.openedPath, '/updates/nudgr-1.2.0-42.apk');
    });

    test('surfaces installer errors', () async {
      service.manifest = _manifest('1.2.0');
      await presenter.checkForUpdates();
      await presenter.downloadUpdate();
      service.installError = 'blocked';

      expect(await presenter.installUpdate(), 'blocked');
    });

    test('errors when nothing was downloaded', () async {
      expect(await presenter.installUpdate(), isNotNull);
    });
  });

  test('dismissUpdate hides the prompt for the session', () async {
    service.manifest = _manifest('1.2.0');
    await presenter.checkForUpdates();
    presenter.dismissUpdate();
    expect(presenter.updateAvailable, isFalse);
    presenter.resetDismissed();
    expect(presenter.updateAvailable, isTrue);
  });
}
