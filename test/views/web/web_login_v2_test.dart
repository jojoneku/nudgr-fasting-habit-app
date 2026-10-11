import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/presenters/auth_presenter.dart';
import 'package:intermittent_fasting/services/auth_service.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/web_login_view.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The v2 login (Plan 063 Phase 10, `Login.dc.html`): a brand panel beside
/// the sign-in panel at the rail breakpoint and wider, stacked under it
/// narrower; the Google button, the theme toggle flipping [webThemeMode],
/// and no guest path — in both themes.
void main() {
  const modes = [true, false];
  String mode(bool dark) => dark ? 'dark' : 'light';

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    bool dark = true,
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: WebLoginViewV2(presenter: AuthPresenter(_SignedOutAuth())),
    ));
    await tester.pumpAndSettle();
  }

  tearDown(() => webThemeMode.value = ThemeMode.dark);

  for (final dark in modes) {
    testWidgets('1440 px: brand panel beside the sign-in panel (${mode(dark)})',
        (tester) async {
      await pump(tester, width: 1440, dark: dark);

      expect(find.byKey(WebKeys.loginBrandPanel), findsOneWidget);
      expect(find.byKey(WebKeys.loginSignInPanel), findsOneWidget);
      final brand = tester.getRect(find.byKey(WebKeys.loginBrandPanel));
      final form = tester.getRect(find.byKey(WebKeys.loginSignInPanel));
      expect(form.left, greaterThanOrEqualTo(brand.right - 1),
          reason: 'side by side');
      expect(brand.height, 900, reason: 'full-height panel');

      expect(find.text('Your finances, on the big screen.'), findsOneWidget);
      expect(find.text('Treasury'), findsOneWidget);
      expect(find.text('Editable ledger'), findsOneWidget);
      expect(find.text('Month-end outlook'), findsOneWidget);
      expect(find.text('Nudgy'), findsOneWidget);
      expect(find.text('EXAMPLE'), findsOneWidget,
          reason: 'the preview card is marked as example copy');
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byKey(WebKeys.loginGoogle), findsOneWidget);
      expect(find.byType(AppPrimaryButton), findsOneWidget);
      expect(find.text('Nudgr Treasury'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
      expect(find.textContaining('later'), findsNothing,
          reason: 'no guest path on web');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('600 px: the panels stack, brand first', (tester) async {
    await pump(tester, width: 600, height: 1400);

    final brand = tester.getRect(find.byKey(WebKeys.loginBrandPanel));
    final form = tester.getRect(find.byKey(WebKeys.loginSignInPanel));
    expect(form.top, greaterThanOrEqualTo(brand.bottom - 1), reason: 'stacked');
    expect(brand.left, form.left);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(WebKeys.loginThemeToggle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the theme toggle flips webThemeMode', (tester) async {
    await pump(tester, width: 1440);
    expect(webThemeMode.value, ThemeMode.dark);
    expect(find.text('Light mode'), findsOneWidget);
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);

    await tester.tap(find.byKey(WebKeys.loginThemeToggle));
    await tester.pumpAndSettle();
    expect(webThemeMode.value, ThemeMode.light);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.byTooltip('Switch to dark mode'), findsOneWidget);

    await tester.tap(find.byKey(WebKeys.loginThemeToggle));
    await tester.pumpAndSettle();
    expect(webThemeMode.value, ThemeMode.dark);
  });

  testWidgets('the toggle keeps a 44 px target', (tester) async {
    await pump(tester, width: 1440);
    final size = tester.getSize(find.byKey(WebKeys.loginThemeToggle));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  });
}

class _SignedOutAuth extends Fake implements AuthService {
  @override
  bool get isSignedIn => false;
  @override
  String? get currentUserId => null;
  @override
  String? get currentUserEmail => null;
  @override
  String? get currentUserDisplayName => null;
  @override
  String? get currentUserAvatarUrl => null;
}
