import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/widgets/ai_chat_sheet.dart';

import '../../mocks.mocks.dart';

/// The staged-image row above the Nudgy input, and the images on a sent
/// bubble.
void main() {
  // A real 1x1 PNG: Image.memory decodes for real in a widget test, and junk
  // bytes fail the test with a codec error.
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

  Future<void> pump(WidgetTester tester, Widget child,
      {ThemeData? theme}) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? buildDarkTheme(),
      home:
          Scaffold(body: Align(alignment: Alignment.bottomLeft, child: child)),
    ));
    await tester.pump();
  }

  group('StagedImagesRow', () {
    testWidgets('draws nothing when no image is staged', (tester) async {
      await pump(tester, StagedImagesRow(images: const [], onRemove: (_) {}));
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('shows one removable thumbnail per staged image',
        (tester) async {
      await pump(
        tester,
        StagedImagesRow(images: [png, png, png], onRemove: (_) {}),
      );
      expect(find.byType(Image), findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey('nudgy.removeImage.$i')), findsOneWidget);
      }
    });

    testWidgets('remove targets are at least 44x44', (tester) async {
      await pump(tester, StagedImagesRow(images: [png], onRemove: (_) {}));
      final size =
          tester.getSize(find.byKey(const ValueKey('nudgy.removeImage.0')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('renders in the light theme too', (tester) async {
      await pump(
        tester,
        StagedImagesRow(images: [png, png], onRemove: (_) {}),
        theme: buildLightTheme(),
      );
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('tapping remove unstages that image in the presenter',
        (tester) async {
      final stats = MockStatsPresenter();
      final cloud = MockAiCoachService();
      when(stats.stats).thenReturn(UserStats.initial());
      when(cloud.isAvailable).thenReturn(true);
      when(cloud.tier).thenReturn(AiCoachTier.cloud);
      final presenter = AiCoachPresenter(stats: stats, service: cloud)
        ..openSession(AiCoachEntryPoint.financeAdvisor);
      addTearDown(presenter.dispose);

      final first = Uint8List.fromList(png);
      final second = Uint8List.fromList(png);
      presenter.addAttachments([first, second]);

      await pump(
        tester,
        ListenableBuilder(
          listenable: presenter,
          builder: (_, __) => StagedImagesRow(
            images: presenter.pendingImages,
            onRemove: presenter.removeAttachment,
          ),
        ),
      );
      expect(find.byType(Image), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('nudgy.removeImage.0')));
      await tester.pump();

      expect(presenter.pendingImages, hasLength(1));
      expect(identical(presenter.pendingImages.single, second), isTrue);
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('MessageImages', () {
    testWidgets('one image shows large, without a thumbnail grid',
        (tester) async {
      await pump(tester, MessageImages(images: [png]));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(const ValueKey('nudgy.messageImage.0')), findsNothing);
    });

    testWidgets('several images all show on the bubble', (tester) async {
      await pump(tester, MessageImages(images: [png, png, png, png]));
      expect(find.byType(Image), findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey('nudgy.messageImage.$i')), findsOneWidget);
      }
    });
  });
}
