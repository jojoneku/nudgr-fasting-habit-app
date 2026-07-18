import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/weight_entry.dart';
import 'package:intermittent_fasting/views/widgets/hub/weight_body_hub_card.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late MockNutritionPresenter nutrition;

  setUp(() {
    nutrition = MockNutritionPresenter();
    when(nutrition.latestWeight).thenReturn(null);
    when(nutrition.weightDelta).thenReturn(null);
    when(nutrition.latestMeasurement).thenReturn(null);
    when(nutrition.estimatedBodyFatPercent).thenReturn(null);
  });

  WeightEntry entry(double kg) => WeightEntry(
        id: '1',
        weightKg: kg,
        loggedAt: DateTime(2026, 7, 16),
      );

  group('WeightBodyHubCard — weight tile', () {
    testWidgets('tap opens the weight-log screen when a weight exists',
        (tester) async {
      when(nutrition.latestWeight).thenReturn(entry(75.0));
      var openedWeight = false;

      await tester.pumpWidget(_wrap(WeightBodyHubCard(
        nutrition: nutrition,
        onOpenBody: () {},
        onOpenWeight: () => openedWeight = true,
      )));
      await tester.tap(find.text('75.0 kg'));
      await tester.pumpAndSettle();

      expect(openedWeight, isTrue);
      expect(find.text('LOG WEIGHT'), findsNothing);
    });

    testWidgets('edit icon opens the inline quick-entry, not the screen',
        (tester) async {
      when(nutrition.latestWeight).thenReturn(entry(75.0));
      var openedWeight = false;

      await tester.pumpWidget(_wrap(WeightBodyHubCard(
        nutrition: nutrition,
        onOpenBody: () {},
        onOpenWeight: () => openedWeight = true,
      )));
      await tester.tap(find.byTooltip('Log weight'));
      await tester.pumpAndSettle();

      expect(openedWeight, isFalse);
      expect(find.text('LOG WEIGHT'), findsOneWidget);
    });

    testWidgets('long-press opens the inline quick-entry', (tester) async {
      when(nutrition.latestWeight).thenReturn(entry(75.0));

      await tester.pumpWidget(_wrap(WeightBodyHubCard(
        nutrition: nutrition,
        onOpenBody: () {},
        onOpenWeight: () {},
      )));
      await tester.longPress(find.text('75.0 kg'));
      await tester.pumpAndSettle();

      expect(find.text('LOG WEIGHT'), findsOneWidget);
    });

    testWidgets('with no weight yet, tap goes straight to quick-entry',
        (tester) async {
      var openedWeight = false;

      await tester.pumpWidget(_wrap(WeightBodyHubCard(
        nutrition: nutrition,
        onOpenBody: () {},
        onOpenWeight: () => openedWeight = true,
      )));
      await tester.tap(find.text('Tap to add').first);
      await tester.pumpAndSettle();

      expect(openedWeight, isFalse);
      expect(find.text('LOG WEIGHT'), findsOneWidget);
    });

    testWidgets('without an onOpenWeight callback, tap falls back to entry',
        (tester) async {
      when(nutrition.latestWeight).thenReturn(entry(75.0));

      await tester.pumpWidget(_wrap(WeightBodyHubCard(
        nutrition: nutrition,
        onOpenBody: () {},
      )));
      await tester.tap(find.text('75.0 kg'));
      await tester.pumpAndSettle();

      expect(find.text('LOG WEIGHT'), findsOneWidget);
    });
  });

  group('WeightBodyHubCard — body tile', () {
    testWidgets('tap opens the body-measurement screen', (tester) async {
      var openedBody = false;

      await tester.pumpWidget(_wrap(WeightBodyHubCard(
        nutrition: nutrition,
        onOpenBody: () => openedBody = true,
      )));
      await tester.tap(find.text('BODY'));
      await tester.pumpAndSettle();

      expect(openedBody, isTrue);
    });
  });
}
