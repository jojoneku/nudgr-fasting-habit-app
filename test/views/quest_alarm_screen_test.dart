import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/alarm_notification.dart';
import 'package:intermittent_fasting/presenters/quest_alarm_presenter.dart';
import 'package:intermittent_fasting/services/lock_screen_service.dart';
import 'package:intermittent_fasting/views/quests/quest_alarm_screen.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockNotificationService notifications;
  late List<String> lockScreenCalls;
  late bool overLockScreen;

  const channel = MethodChannel(LockScreenService.channelName);

  setUp(() {
    notifications = MockNotificationService();
    lockScreenCalls = [];
    overLockScreen = true;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      lockScreenCalls.add(call.method);
      if (call.method == 'isShowingOverLockScreen') return overLockScreen;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  QuestAlarmPresenter presenterFor(AlarmNotification alarm) =>
      QuestAlarmPresenter(
        alarm: alarm,
        notifications: notifications,
        lockScreen: LockScreenService(channel: channel),
      );

  Future<QuestAlarmPresenter> pump(
      WidgetTester tester, AlarmNotification alarm) async {
    final presenter = presenterFor(alarm);
    await tester.pumpWidget(MaterialApp(
      home: QuestAlarmScreen(alarm: alarm, presenter: presenter),
    ));
    await tester.pump();
    return presenter;
  }

  const questAlarm = AlarmNotification(
    questId: 7,
    title: 'Take meds',
    body: "It's time for your quest!",
  );

  const milestoneAlarm = AlarmNotification(
    title: 'You did it!',
    body: 'Fasting goal reached.',
  );

  group('QuestAlarmScreen', () {
    testWidgets('shows the reminder and nothing else', (tester) async {
      final p = await pump(tester, questAlarm);
      expect(find.text('Take meds'), findsOneWidget);
      expect(find.text("It's time for your quest!"), findsOneWidget);
      expect(find.text('Mark as Done'), findsOneWidget);
      expect(find.text('Snooze 15m'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      p.dispose();
    });

    testWidgets('a milestone alarm offers only dismiss', (tester) async {
      final p = await pump(tester, milestoneAlarm);
      expect(find.text('You did it!'), findsOneWidget);
      expect(find.text('Mark as Done'), findsNothing);
      expect(find.text('Snooze 15m'), findsNothing);
      expect(find.text('Dismiss'), findsOneWidget);
      p.dispose();
    });

    testWidgets('action buttons clear the 44px minimum touch target',
        (tester) async {
      final p = await pump(tester, questAlarm);
      for (final label in ['Mark as Done', 'Snooze 15m', 'Dismiss']) {
        // byWidgetPredicate, not byType: ButtonStyleButton is abstract and
        // byType matches the exact runtime type only.
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      }
      p.dispose();
    });

    testWidgets('acquires the lock-screen flags on open', (tester) async {
      final p = await pump(tester, questAlarm);
      expect(lockScreenCalls, contains('acquire'));
      p.dispose();
    });

    // The leak this whole change exists to close: whatever sits behind the
    // alarm screen must not be left visible on a locked phone.
    testWidgets('dismiss releases the lock-screen flags', (tester) async {
      final p = await pump(tester, questAlarm);
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(lockScreenCalls, contains('release'));
      p.dispose();
    });

    testWidgets('mark as done queues the completion, then releases',
        (tester) async {
      when(notifications.completeQuestFromAlarm(any))
          .thenAnswer((_) async {});
      final p = await pump(tester, questAlarm);
      await tester.tap(find.text('Mark as Done'));
      await tester.pump();
      verify(notifications.completeQuestFromAlarm(7)).called(1);
      expect(lockScreenCalls, contains('release'));
      p.dispose();
    });

    testWidgets('snooze keeps the alarm style so it wakes the screen again',
        (tester) async {
      when(notifications.showQuestSnooze(any, any,
              alarmStyle: anyNamed('alarmStyle')))
          .thenAnswer((_) async {});
      final p = await pump(tester, questAlarm);
      await tester.tap(find.text('Snooze 15m'));
      await tester.pump();
      verify(notifications.showQuestSnooze(7, 'Take meds', alarmStyle: true))
          .called(1);
      p.dispose();
    });

    // Half-asleep double taps are the normal case for an alarm, so the side
    // effect must fire once even if the button is hit twice.
    testWidgets('a repeat tap after closing is ignored', (tester) async {
      when(notifications.completeQuestFromAlarm(any))
          .thenAnswer((_) async {});
      when(notifications.showQuestSnooze(any, any,
              alarmStyle: anyNamed('alarmStyle')))
          .thenAnswer((_) async {});
      final p = await pump(tester, questAlarm);
      await p.markDone();
      await p.markDone();
      await p.snooze();
      await p.dismiss();
      verify(notifications.completeQuestFromAlarm(7)).called(1);
      verifyNever(notifications.showQuestSnooze(any, any,
          alarmStyle: anyNamed('alarmStyle')));
      p.dispose();
    });
  });

  group('QuestAlarmPresenter close routing', () {
    test('over the lock screen, closing returns to the lock screen', () async {
      overLockScreen = true;
      final p = presenterFor(questAlarm);
      await p.init();
      await p.dismiss();
      expect(p.closeRequest.value, AlarmDismissal.returnToLockScreen);
      p.dispose();
    });

    test('unlocked, closing just pops the alarm route', () async {
      overLockScreen = false;
      final p = presenterFor(questAlarm);
      await p.init();
      await p.dismiss();
      expect(p.closeRequest.value, AlarmDismissal.popRoute);
      p.dispose();
    });
  });
}
