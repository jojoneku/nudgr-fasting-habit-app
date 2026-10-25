import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/app_lock/app_lock_policy.dart';
import 'package:intermittent_fasting/presenters/app_lock_presenter.dart';
import 'package:intermittent_fasting/services/app_lock/app_lock_remote.dart';
import 'package:intermittent_fasting/services/app_lock/pin_hasher.dart';
import 'package:intermittent_fasting/views/app_lock/app_lock_activity_detector.dart';
import 'package:intermittent_fasting/views/app_lock/app_lock_settings.dart';
import 'package:intermittent_fasting/views/app_lock/pin_entry_flow.dart';

import '../support/app_lock_fakes.dart';

void main() {
  late FakeLockStorage storage;
  late FakeVerifierCache cache;
  late FakeLockRemote remote;
  late FakeLockAuth auth;
  late DateTime now;
  final hasher = PinHasher(iterations: 200, offThread: false);

  setUp(() {
    storage = FakeLockStorage();
    cache = FakeVerifierCache();
    remote = FakeLockRemote();
    auth = FakeLockAuth();
    now = DateTime(2026, 10, 25, 9);
  });

  Future<AppLockPresenter> signedIn(WidgetTester tester,
      {bool web = false}) async {
    final p = AppLockPresenter(
      storage: storage,
      cache: cache,
      remote: remote,
      policy: web ? AppLockPolicy.web : AppLockPolicy.mobile,
      hasher: hasher,
      privacy: FakePrivacy(),
      clock: () => now,
    );
    await tester.runAsync(() async {
      await p.init();
      p.bindAuth(auth.asLockAuth);
      auth.signIn('u');
      await Future<void>.delayed(Duration.zero);
    });
    return p;
  }

  Future<void> enter(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.bySemanticsLabel(d));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  group('PinEntryFlow (create)', () {
    Future<List<bool>> pumpFlow(WidgetTester tester, AppLockPresenter p) async {
      final done = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PinEntryFlow(
            presenter: p,
            mode: PinFlowMode.create,
            onDone: done.add,
          ),
        ),
      ));
      return done;
    }

    testWidgets('a mismatch starts over and sets nothing', (tester) async {
      final p = await signedIn(tester);
      final done = await pumpFlow(tester, p);
      await tester.tap(find.text('4 digits'));
      await tester.pump();
      await enter(tester, '1234');
      expect(find.text('Enter the PIN again'), findsOneWidget);
      await enter(tester, '9999');
      expect(find.text('PINs do not match. Try again.'), findsOneWidget);
      expect(find.text('Choose a PIN'), findsOneWidget);
      expect(done, isEmpty);
      expect(p.isEnabled, isFalse);
    });

    testWidgets('a confirmed PIN turns the lock on', (tester) async {
      final p = await signedIn(tester);
      final done = await pumpFlow(tester, p);
      await tester.tap(find.text('4 digits'));
      await tester.pump();
      await enter(tester, '1234');
      await enter(tester, '1234');
      expect(done, [true]);
      expect(p.isEnabled, isTrue);
      expect(remote.rows['u'], isNotNull);
    });

    testWidgets('offline shows the reason and a retry', (tester) async {
      final p = await signedIn(tester);
      final done = await pumpFlow(tester, p);
      remote.failWith = AppLockRemoteFailure.offline;
      await tester.tap(find.text('4 digits'));
      await tester.pump();
      await enter(tester, '1234');
      await enter(tester, '1234');
      expect(find.text(AppLockPresenter.offlineMessage), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(done, isEmpty);

      remote.failWith = null;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(done, [true]);
    });
  });

  group('AppLockSettingsTiles', () {
    testWidgets('signed out shows the sign-in hint only', (tester) async {
      final p = AppLockPresenter(
        storage: storage,
        cache: cache,
        remote: remote,
        policy: AppLockPolicy.mobile,
        hasher: hasher,
        privacy: FakePrivacy(),
      );
      await tester.runAsync(p.init);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AppLockSettingsTiles(presenter: p)),
      ));
      expect(find.text('Sign in to use app lock'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('lock on shows the device rows, web has no biometrics',
        (tester) async {
      final p = await signedIn(tester, web: true);
      await tester.runAsync(() => p.setNewPin('1234'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AppLockSettingsTiles(presenter: p)),
      ));
      expect(find.text('Lock after'), findsOneWidget);
      expect(find.text('After 5 minutes'), findsOneWidget);
      expect(find.text('Change PIN'), findsOneWidget);
      expect(find.text('Lock now'), findsOneWidget);
      expect(find.text('Use fingerprint or face'), findsNothing);

      await tester.tap(find.text('Lock now'));
      expect(p.isLocked, isTrue);
    });
  });

  group('AppLockActivityDetector', () {
    testWidgets('pointer and key input count as activity', (tester) async {
      final p = await signedIn(tester, web: true);
      await tester.runAsync(() => p.setNewPin('1234'));
      await tester.pumpWidget(MaterialApp(
        home: AppLockActivityDetector(
          presenter: p,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ));

      now = now.add(const Duration(minutes: 4));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(10, 10));
      await gesture.moveTo(const Offset(20, 20));
      await tester.pump();

      now = now.add(const Duration(minutes: 4));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);

      // 8 min since the PIN was set, but only 0 since the last key.
      now = now.add(const Duration(minutes: 4, seconds: 59));
      p.onForegrounded();
      expect(p.isLocked, isFalse);

      now = now.add(const Duration(seconds: 2));
      p.onForegrounded();
      expect(p.isLocked, isTrue);
      await gesture.removePointer();
    });
  });
}
