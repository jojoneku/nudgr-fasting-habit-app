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

/// The Money Mentor chat surface: header layout, selectable replies, and the
/// scroll contract — follow the newest message while the user is parked at the
/// tail, and never move the list under them otherwise.
void main() {
  late MockStatsPresenter stats;
  late MockAiCoachService cloud;

  setUp(() {
    stats = MockStatsPresenter();
    cloud = MockAiCoachService();
    when(stats.stats).thenReturn(UserStats.initial());
    when(cloud.isAvailable).thenReturn(true);
    when(cloud.tier).thenReturn(AiCoachTier.cloud);
    when(cloud.downloadProgress).thenReturn(null);
  });

  AiCoachPresenter openAdvisor() {
    final presenter = AiCoachPresenter(stats: stats, service: cloud);
    presenter.openSession(AiCoachEntryPoint.financeAdvisor);
    return presenter;
  }

  /// Settled assistant lines, enough of them to overflow the viewport.
  void seed(AiCoachPresenter presenter, int count) {
    for (var i = 0; i < count; i++) {
      presenter.appendAssistantNote('Reply $i about your budget this month.');
    }
  }

  Future<void> pumpChat(
    WidgetTester tester,
    AiCoachPresenter presenter, {
    Size surface = const Size(393, 852),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: AiChatBody(
          presenter: presenter,
          entryPoint: AiCoachEntryPoint.financeAdvisor,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The message list's scroll position. Scoped to the list because the
  /// composer's TextField owns a Scrollable of its own.
  ScrollPosition listPosition(WidgetTester tester) {
    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    return tester.state<ScrollableState>(scrollable).position;
  }

  /// The jump button never leaves the tree — it fades, so visibility is read
  /// off its opacity rather than by finding it.
  double jumpButtonOpacity(WidgetTester tester) {
    final fade = find.ancestor(
      of: find.byIcon(Icons.arrow_downward_rounded),
      matching: find.byType(AnimatedOpacity),
    );
    return tester.widget<AnimatedOpacity>(fade).opacity;
  }

  group('header', () {
    testWidgets('the title keeps every pixel the controls do not need',
        (tester) async {
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);

      // The regression: the title was a Flexible beside a Spacer. Both are
      // flex 1, so they split the free width — the title was handed half of it
      // and ellipsised to "Money Men…" with an empty gap sitting next to it.
      //
      // Asserted as "no gap between the title and the first trailing control"
      // rather than "the text is not ellipsised", because widget tests render
      // in Ahem, whose every glyph is a full em wide — about 1.7x the real
      // Plus Jakarta Sans advance. Any width-vs-content assertion measures the
      // test font, not the layout. The gap does measure the layout, and it is
      // what a Spacer stealing half the row actually looks like.
      final title = find.text('Money Mentor');
      expect(title, findsOneWidget);

      final titleRight = tester.getRect(title).right;
      final firstControlLeft =
          tester.getRect(find.byType(IconButton).first).left;
      expect(firstControlLeft - titleRight, lessThan(12),
          reason: 'only the 6px spacer belongs between them; the old Spacer '
              'left roughly half the row empty');

      presenter.dispose();
    });

    testWidgets('drops the redundant AI badge beside the persona label',
        (tester) async {
      // "Money Mentor" + a Think/Fast toggle already says this is the AI; the
      // badge was ~40px of the squeeze on the title. It stays in the web dock,
      // which prints no label.
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);

      expect(find.text('Money Mentor'), findsOneWidget);
      expect(find.text('AI'), findsNothing);

      presenter.dispose();
    });
  });

  group('selection', () {
    testWidgets('wraps the conversation so replies can be copied out',
        (tester) async {
      final presenter = openAdvisor();
      seed(presenter, 3);
      await pumpChat(tester, presenter);

      expect(find.byType(SelectionArea), findsOneWidget);

      presenter.dispose();
    });
  });

  group('scroll contract', () {
    testWidgets('opens on the newest message with no jump button offered',
        (tester) async {
      final presenter = openAdvisor();
      seed(presenter, 40);
      await pumpChat(tester, presenter);

      final position = listPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));
      expect(jumpButtonOpacity(tester), 0);

      presenter.dispose();
    });

    testWidgets('the jump button appears off screen and rides back down',
        (tester) async {
      final presenter = openAdvisor();
      seed(presenter, 40);
      await pumpChat(tester, presenter);

      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(jumpButtonOpacity(tester), 1);

      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      await tester.pumpAndSettle();

      final position = listPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));
      expect(jumpButtonOpacity(tester), 0);

      presenter.dispose();
    });

    testWidgets('a rebuild that carries no new content leaves the position',
        (tester) async {
      // The regression behind "screenshotting scrolls the chat to the bottom":
      // the list scrolled to the end from inside its builder, so *any* rebuild
      // — a metrics change, a toggle, the keyboard — yanked the user out of the
      // history they were reading.
      final presenter = openAdvisor();
      seed(presenter, 40);
      await pumpChat(tester, presenter);

      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      final readingAt = listPosition(tester).pixels;

      // A notification that changes no message content, then a fresh frame:
      // the shape every incidental rebuild takes.
      presenter.toggleThinking();
      await tester.pumpAndSettle();

      expect(listPosition(tester).pixels, closeTo(readingAt, 1));

      presenter.dispose();
    });

    testWidgets('new content while reading history waits for the user',
        (tester) async {
      final presenter = openAdvisor();
      seed(presenter, 40);
      await pumpChat(tester, presenter);

      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      final readingAt = listPosition(tester).pixels;

      presenter.appendAssistantNote('One more thing about your rent.');
      await tester.pumpAndSettle();

      expect(listPosition(tester).pixels, closeTo(readingAt, 1));
      expect(jumpButtonOpacity(tester), 1);

      presenter.dispose();
    });

    testWidgets('follows the newest message while parked at the bottom',
        (tester) async {
      final presenter = openAdvisor();
      seed(presenter, 40);
      await pumpChat(tester, presenter);

      presenter.appendAssistantNote('And here is the summary you asked for.');
      await tester.pumpAndSettle();

      final position = listPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));

      presenter.dispose();
    });
  });
}
