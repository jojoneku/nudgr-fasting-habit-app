import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/app_lock/app_lock_policy.dart';
import 'package:intermittent_fasting/models/app_lock/pin_verifier.dart';
import 'package:intermittent_fasting/presenters/app_lock_presenter.dart';
import 'package:intermittent_fasting/services/app_lock/pin_hasher.dart';
import 'package:intermittent_fasting/views/app_lock/app_lock_gate.dart';
import 'package:intermittent_fasting/views/app_lock/pin_pad.dart';

import '../support/app_lock_fakes.dart';

const _pin = '1234';

void main() {
  final hasher = PinHasher(iterations: 200, offThread: false);
  late PinVerifier verifier;

  setUpAll(() async {
    verifier = await hasher.hash(_pin);
  });

  group('PinPad', () {
    Future<List<String>> pumpPad(WidgetTester tester,
        {bool enabled = true}) async {
      final completed = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PinPad(
              length: 4,
              enabled: enabled,
              onCompleted: completed.add,
            ),
          ),
        ),
      ));
      return completed;
    }

    Future<void> tapDigits(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.bySemanticsLabel(d));
        await tester.pump();
      }
    }

    testWidgets('reports the PIN once every digit is in', (tester) async {
      final completed = await pumpPad(tester);
      await tapDigits(tester, '123');
      expect(completed, isEmpty);
      await tapDigits(tester, '4');
      await tester.pump(const Duration(milliseconds: 150));
      expect(completed, ['1234']);
    });

    testWidgets('announces the count, never the digits', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPad(tester);
      await tapDigits(tester, '73');
      expect(find.bySemanticsLabel('2 of 4 digits entered'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('73')), findsNothing);
      handle.dispose();
    });

    testWidgets('backspace removes a digit', (tester) async {
      final completed = await pumpPad(tester);
      await tapDigits(tester, '12');
      await tester.tap(find.bySemanticsLabel('Delete digit'));
      await tester.pump();
      await tapDigits(tester, '345');
      await tester.pump(const Duration(milliseconds: 150));
      expect(completed, ['1345']);
    });

    testWidgets('physical digit keys work', (tester) async {
      final completed = await pumpPad(tester);
      for (final key in [
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit6,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump(const Duration(milliseconds: 150));
      expect(completed, ['9876']);
    });

    testWidgets('a disabled pad ignores input', (tester) async {
      final completed = await pumpPad(tester, enabled: false);
      await tapDigits(tester, '1234');
      await tester.pump(const Duration(milliseconds: 150));
      expect(completed, isEmpty);
    });

    testWidgets('keys are at least 64 px', (tester) async {
      await pumpPad(tester);
      final size = tester.getSize(find.bySemanticsLabel('5'));
      expect(size.width, greaterThanOrEqualTo(64));
      expect(size.height, greaterThanOrEqualTo(64));
    });
  });

  group('AppLockGate', () {
    late FakeLockStorage storage;
    late FakeVerifierCache cache;
    late FakeLockRemote remote;
    late FakeLockAuth auth;

    setUp(() {
      storage = FakeLockStorage();
      cache = FakeVerifierCache()..value = verifier;
      remote = FakeLockRemote()..rows['u'] = verifier;
      auth = FakeLockAuth();
    });

    AppLockPresenter build() => AppLockPresenter(
          storage: storage,
          cache: cache,
          remote: remote,
          policy: AppLockPolicy.mobile,
          hasher: hasher,
          privacy: FakePrivacy(),
        );

    Future<int> pumpApp(WidgetTester tester, AppLockPresenter presenter,
        {ThemeData? theme}) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        builder: (context, child) =>
            AppLockGate(presenter: presenter, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  taps++;
                  showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(
                      content: TextField(key: Key('note')),
                    ),
                  );
                },
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return taps;
    }

    Future<void> enterPin(WidgetTester tester, String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.bySemanticsLabel(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 150));
      // Let the async verify and the unlock notify settle.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    testWidgets('blank before init, then the lock screen', (tester) async {
      final presenter = build();
      await pumpApp(tester, presenter);
      expect(find.text('Enter PIN'), findsNothing);
      expect(presenter.isGated, isTrue);
      await tester.runAsync(presenter.init);
      await tester.pump();
      expect(find.text('Enter PIN'), findsOneWidget);
    });

    testWidgets('covers an open dialog and keeps its state across unlock',
        (tester) async {
      final presenter = build();
      await tester.runAsync(presenter.init);
      auth.restore('u');
      presenter.bindAuth(auth.asLockAuth);
      await tester.runAsync(() => presenter.submitPin(_pin)); // start open
      await pumpApp(tester, presenter);

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note')), 'lunch 250');

      presenter.lockNow();
      await tester.pump();
      expect(find.text('Enter PIN'), findsOneWidget);
      // The dialog is still mounted underneath but unreachable.
      expect(find.byKey(const Key('note')), findsOneWidget);
      expect(find.byKey(const Key('note')).hitTestable(), findsNothing);

      await enterPin(tester, _pin);
      expect(presenter.isLocked, isFalse);
      expect(find.text('Enter PIN'), findsNothing);
      expect(find.text('lunch 250'), findsOneWidget);
    });

    testWidgets('taps never reach the app while locked', (tester) async {
      final presenter = build();
      await tester.runAsync(presenter.init);
      await pumpApp(tester, presenter);
      expect(find.text('Open form').hitTestable(), findsNothing);
    });

    testWidgets('Android Back is held while gated', (tester) async {
      final presenter = build();
      await tester.runAsync(presenter.init);
      final guard = AppLockBackGuard(presenter);
      // Attached before the app is built, as the roots do.
      guard.attach();
      addTearDown(guard.detach);
      expect(await guard.didPopRoute(), isTrue);
      await tester.runAsync(() async {
        auth.restore('u');
        presenter.bindAuth(auth.asLockAuth);
        await presenter.submitPin(_pin);
      });
      expect(await guard.didPopRoute(), isFalse);
    });

    testWidgets('renders in light and dark themes', (tester) async {
      for (final theme in [ThemeData.light(), ThemeData.dark()]) {
        final presenter = build();
        await tester.runAsync(presenter.init);
        await pumpApp(tester, presenter, theme: theme);
        expect(find.text('Enter PIN'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a wrong PIN shows the error and stays locked', (tester) async {
      final presenter = build();
      await tester.runAsync(presenter.init);
      await pumpApp(tester, presenter);
      await enterPin(tester, '9999');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(presenter.isLocked, isTrue);
    });
  });
}
