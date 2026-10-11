import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../presenters/auth_presenter.dart';
import '../../utils/app_spacing.dart';
import '../widgets/system/system.dart';
import 'design/web_breakpoints.dart';
import 'design/web_constants.dart';
import 'design/web_theme.dart';
import 'web_flags.dart';
import 'web_keys.dart';

/// Signed-out screen for the Treasury web companion (Plan 042). Unlike the
/// mobile [LoginView], this is an always-mounted view the shell swaps in based
/// on auth state — Google sign-in here triggers a full-page OAuth redirect, so
/// there is no "log in later" guest path on web (cloud data is the whole point).
///
/// Behind [kWebV2] it is the split layout of `Login.dc.html` ([WebLoginViewV2]);
/// off the flag the pre-v2 centred card is unchanged, so the live site keeps
/// its login until Phase 11 flips the build.
class WebLoginView extends StatelessWidget {
  final AuthPresenter presenter;

  const WebLoginView({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    if (kWebV2) return WebLoginViewV2(presenter: presenter);
    return _WebLoginLegacy(presenter: presenter);
  }
}

/// Surfaces a sign-in error as a toast once, then clears it on the presenter.
void _flushError(BuildContext context, AuthPresenter presenter) {
  final err = presenter.error;
  if (err == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    AppToast.error(context, err);
    presenter.clearError();
  });
}

/// The pre-v2 login: logo, title, tagline and the Google button, centred.
class _WebLoginLegacy extends StatelessWidget {
  final AuthPresenter presenter;

  const _WebLoginLegacy({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListenableBuilder(
            listenable: presenter,
            builder: (context, _) {
              _flushError(context, presenter);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/img/nudgr_icon_nobg_colored.png',
                        width: 88,
                        height: 88,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: Text(
                        'Treasury',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Center(
                      child: Text(
                        'Your finances, on the big screen.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppPrimaryButton(
                      label: 'Continue with Google',
                      isLoading: presenter.isLoading,
                      onPressed: presenter.isLoading
                          ? null
                          : presenter.signInWithGoogle,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The v2 login (Plan 063 Phase 10, `Login.dc.html`): at the rail breakpoint
/// and wider, a brand panel on the left — the Treasury hero gradient, the
/// Nudgr mark, the headline, three feature chips and an example net-worth
/// card — beside a sign-in panel with the theme toggle, the Google button,
/// two trust lines and a footer. Narrower, the two panels stack.
///
/// Same auth call, loading state and error toast as the pre-v2 view.
class WebLoginViewV2 extends StatelessWidget {
  final AuthPresenter presenter;

  const WebLoginViewV2({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= WebBreakpoints.rail;
          if (split) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: _BrandPanel(stacked: false)),
                Expanded(
                  child: _SignInPanel(presenter: presenter, stacked: false),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _BrandPanel(stacked: true),
                _SignInPanel(presenter: presenter, stacked: true),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The left (or top) panel: the hero gradient with the brand and the pitch.
class _BrandPanel extends StatelessWidget {
  final bool stacked;

  const _BrandPanel({required this.stacked});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    final accent = appColors.fast;
    final isDark = theme.brightness == Brightness.dark;
    final surface = cs.surface;
    Color blend(double alpha) =>
        Color.alphaBlend(accent.withValues(alpha: alpha), surface);

    final brand = Row(
      children: [
        Image.asset(
          'assets/img/nudgr_icon_nobg_colored.png',
          width: 36,
          height: 36,
        ),
        const SizedBox(width: WebInsets.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Treasury',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.36,
                color: cs.onSurface,
              ),
            ),
            Text(
              'Nudgr · web companion',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ],
        ),
      ],
    );

    final pitch = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Your finances, on the big screen.',
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: stacked ? 32 : 44,
              fontWeight: FontWeight.w800,
              letterSpacing: stacked ? -0.96 : -1.32,
              height: 1.02,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              'The same ledger, bills, budget and goals your phone syncs — '
              'with a desktop table, a month-end outlook and Nudgy one click '
              'away.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FeatureChip(label: 'Editable ledger', color: accent),
              _FeatureChip(
                  label: 'Month-end outlook', color: appColors.treasury),
              _FeatureChip(label: 'Nudgy', color: appColors.success),
            ],
          ),
        ],
      ),
    );

    final preview = _PreviewCard(accent: accent);

    return Container(
      key: WebKeys.loginBrandPanel,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            blend(isDark ? 0.30 : 0.16),
            blend(isDark ? 0.16 : 0.08),
            surface,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border(
          right: stacked
              ? BorderSide.none
              : BorderSide(
                  color: accent.withValues(alpha: isDark ? 0.35 : 0.22)),
          bottom: stacked
              ? BorderSide(
                  color: accent.withValues(alpha: isDark ? 0.35 : 0.22))
              : BorderSide.none,
        ),
      ),
      padding: EdgeInsets.all(stacked ? WebInsets.xl : 48),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                brand,
                const SizedBox(height: WebInsets.xxl),
                pitch,
                const SizedBox(height: WebInsets.xxl),
                preview,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brand,
                const Spacer(),
                pitch,
                const Spacer(),
                preview,
              ],
            ),
    );
  }
}

/// A tinted pill naming one thing the web does.
class _FeatureChip extends StatelessWidget {
  final String label;
  final Color color;

  const _FeatureChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// A slice of the dashboard with example copy — the figure is a placeholder
/// marked as such, never a real balance (nobody is signed in yet).
class _PreviewCard extends StatelessWidget {
  final Color accent;

  const _PreviewCard({required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;
    final label = theme.textTheme.labelSmall?.copyWith(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.84,
      color: cs.onSurfaceVariant,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('NET WORTH', style: label),
                const SizedBox(width: WebInsets.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('EXAMPLE', style: label?.copyWith(color: muted)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '₱ ···,···.··',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1,
                color: cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your balance, synced from your phone, goes here.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(
                  line: accent,
                  dot: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The canvas' illustrative sparkline: a fixed rising polyline, no data.
class _SparklinePainter extends CustomPainter {
  final Color line;
  final Color dot;

  const _SparklinePainter({required this.line, required this.dot});

  static const _points = [
    Offset(0, 40),
    Offset(50, 36),
    Offset(100, 38),
    Offset(150, 28),
    Offset(200, 24),
    Offset(250, 16),
    Offset(300, 8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 300;
    final sy = size.height / 48;
    final path = Path();
    for (var i = 0; i < _points.length; i++) {
      final p = Offset(_points[i].dx * sx, _points[i].dy * sy);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final last = _points.last;
    canvas.drawCircle(
      Offset(last.dx * sx, last.dy * sy),
      3.5,
      Paint()..color = dot,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.line != line || old.dot != dot;
}

/// The right (or bottom) panel: theme toggle, "Sign in", the Google button,
/// the trust lines and the footer.
class _SignInPanel extends StatelessWidget {
  final AuthPresenter presenter;
  final bool stacked;

  const _SignInPanel({required this.presenter, required this.stacked});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Sign in',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.52,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use the Google account you use on your phone, so the web sees '
            'the same data.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: WebInsets.xl),
          ListenableBuilder(
            listenable: presenter,
            builder: (context, _) {
              _flushError(context, presenter);
              return KeyedSubtree(
                key: WebKeys.loginGoogle,
                child: AppPrimaryButton(
                  label: 'Continue with Google',
                  isLoading: presenter.isLoading,
                  onPressed:
                      presenter.isLoading ? null : presenter.signInWithGoogle,
                ),
              );
            },
          ),
          const SizedBox(height: WebInsets.xl),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: WebInsets.lg),
          _TrustLine(
            icon: Icons.shield_outlined,
            color: appColors.success,
            text: 'Your data stays in your own account. Nothing here is '
                'shared with other users.',
          ),
          const SizedBox(height: 10),
          _TrustLine(
            icon: Icons.sync_rounded,
            color: appColors.fast,
            text: 'Changes you make here show on your phone after its next '
                'sync.',
          ),
        ],
      ),
    );

    final footer = DefaultTextStyle(
      style: theme.textTheme.bodySmall!.copyWith(
        fontSize: 12,
        color: appColors.textMuted,
      ),
      child: const Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          Text('Nudgr Treasury'),
          Text('Privacy'),
          Text('Help'),
        ],
      ),
    );

    const toggle = Align(
      alignment: Alignment.centerRight,
      child: _LoginThemeToggle(),
    );

    if (stacked) {
      return Padding(
        key: WebKeys.loginSignInPanel,
        padding: const EdgeInsets.all(WebInsets.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            toggle,
            const SizedBox(height: WebInsets.xl),
            form,
            const SizedBox(height: WebInsets.xxl),
            footer,
          ],
        ),
      );
    }

    return Padding(
      key: WebKeys.loginSignInPanel,
      padding: const EdgeInsets.fromLTRB(40, WebInsets.xl, 40, WebInsets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toggle,
          Expanded(
            child: Center(
              child: SingleChildScrollView(child: form),
            ),
          ),
          footer,
        ],
      ),
    );
  }
}

/// One shield / sync reassurance under the button.
class _TrustLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _TrustLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The login page's light/dark switch; flips [webThemeMode] like the shell's
/// topbar toggle, with the same tooltips.
class _LoginThemeToggle extends StatelessWidget {
  const _LoginThemeToggle();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: webThemeMode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return Tooltip(
          message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          child: TextButton.icon(
            key: WebKeys.loginThemeToggle,
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              minimumSize: const Size(kWebHitTarget, kWebHitTarget),
              padding: const EdgeInsets.symmetric(horizontal: WebInsets.md),
            ),
            onPressed: () =>
                webThemeMode.value = isDark ? ThemeMode.light : ThemeMode.dark,
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 16,
            ),
            label: Text(isDark ? 'Light mode' : 'Dark mode'),
          ),
        );
      },
    );
  }
}
