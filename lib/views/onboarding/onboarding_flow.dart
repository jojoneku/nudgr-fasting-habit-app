import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../presenters/onboarding_presenter.dart';
import '../../utils/app_motion.dart';
import '../../utils/app_spacing.dart';
import '../nutrition/widgets/tdee_step_forms.dart';
import '../widgets/protocol_card.dart';
import '../widgets/system/system.dart';

/// First-run "Awakening" wizard. A [PageView]-style stepped flow driven by
/// [OnboardingPresenter.step]. Pops when the user completes, skips, or accepts
/// the welcome-back fast-forward — the caller (AppShell) then finishes wiring.
///
/// Nudgr language: blue [AppThemeExtension.fast] for primary actions, gold
/// [AppThemeExtension.gold] reserved for the System-notice / Status-window /
/// First-quest moments. Theme-aware colors only.
class OnboardingFlow extends StatefulWidget {
  final OnboardingPresenter presenter;
  const OnboardingFlow({super.key, required this.presenter});

  static Future<void> show(
    BuildContext context,
    OnboardingPresenter presenter,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingFlow(presenter: presenter),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  bool _wasSignedIn = false;

  OnboardingPresenter get p => widget.presenter;

  @override
  void initState() {
    super.initState();
    // Seed the Vessel controllers from any prefilled draft (replay path).
    if (p.weightKg != null) _weightCtrl.text = _trimNum(p.weightKg!);
    if (p.heightCm != null) _heightCtrl.text = _trimNum(p.heightCm!);
    if (p.ageYears != null) _ageCtrl.text = '${p.ageYears}';
    _wasSignedIn = p.isSignedIn;
    p.addListener(_onPresenterChanged);
  }

  @override
  void dispose() {
    p.removeListener(_onPresenterChanged);
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  void _onPresenterChanged() {
    if (!mounted) return;
    final err = p.authError;
    if (err != null) {
      AppToast.error(context, err);
      p.clearAuthError();
    }
    // Sign-in just completed while on the Identity step: fast-forward if a cloud
    // profile was pulled, otherwise advance into the profile steps.
    if (!_wasSignedIn && p.isSignedIn && p.step == 1) {
      if (!p.cloudProfileFound) p.advance();
    }
    _wasSignedIn = p.isSignedIn;
    setState(() {});
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  Future<void> _skipAndClose() async {
    await p.skip();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _completeAndClose() async {
    await p.complete();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _fastForwardAndClose() async {
    await p.fastForwardFromCloud();
    if (mounted) Navigator.of(context).pop();
  }

  void _syncBodyFromControllers() {
    p.setBody(
      weightKg: double.tryParse(_weightCtrl.text.trim()),
      heightCm: double.tryParse(_heightCtrl.text.trim()),
      ageYears: int.tryParse(_ageCtrl.text.trim()),
    );
  }

  bool get _bodyValid =>
      double.tryParse(_weightCtrl.text.trim()) != null &&
      double.tryParse(_heightCtrl.text.trim()) != null &&
      int.tryParse(_ageCtrl.text.trim()) != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // The flow controls its own dismissal via Skip/Complete.
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                step: p.step,
                showBack: p.step > 0,
                onBack: p.back,
                onSkip: p.advance, // skip THIS step (advance); not a full bail
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.appear,
                  switchInCurve: AppMotion.easeOut,
                  child: KeyedSubtree(
                    key: ValueKey(p.step),
                    child: _buildStep(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (p.step) {
      0 => _awakening(),
      1 => _identity(),
      2 => _vessel(),
      3 => _training(),
      4 => _path(),
      5 => _statusWindow(),
      6 => _protocol(),
      7 => _summons(),
      8 => _review(),
      9 => _firstQuest(),
      _ => const SizedBox.shrink(),
    };
  }

  // ── Reusable pieces ──────────────────────────────────────────────────────────

  Widget _stepScaffold({
    required Widget body,
    required Widget cta,
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            child: body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          child: cta,
        ),
      ],
    );
  }

  // ── Step 0 · Awakening ────────────────────────────────────────────────────────
  Widget _awakening() {
    final theme = Theme.of(context);
    final fast = context.appColors.fast;
    return _stepScaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fast.withValues(alpha: 0.12),
              ),
              child: Icon(Icons.bolt, color: fast, size: 38),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              "Let's set you up",
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'A quick setup builds your profile, sets your daily targets, and '
              'picks your first fasting protocol.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
      cta: Column(
        children: [
          AppPrimaryButton(label: 'Get started', onPressed: p.advance),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _skipAndClose,
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }

  // ── Step 1 · Identity ──────────────────────────────────────────────────────────
  Widget _identity() {
    if (p.cloudProfileFound) {
      return _stepScaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TdeeHeading('Welcome back',
                'We found your record in the cloud. Pick up right where you left off.'),
            _InfoBanner(
              icon: Icons.cloud_done,
              color: context.appColors.fast,
              text:
                  'Your saved profile was restored — no need to set it up again.',
            ),
          ],
        ),
        cta: AppPrimaryButton(
          label: 'Continue to Hub',
          onPressed: _fastForwardAndClose,
        ),
      );
    }
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TdeeHeading('Sign in',
              'Sync across devices — or continue on this device only.'),
          _InfoBanner(
            icon: Icons.shield_outlined,
            color: context.appColors.fast,
            text: 'Guest mode keeps everything on your device. '
                'You can sign in later without losing data.',
          ),
        ],
      ),
      cta: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppPrimaryButton(
            label: 'Continue with Google',
            leading: Icons.login,
            isLoading: p.authLoading,
            onPressed: p.authLoading ? null : p.signInWithGoogle,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppSecondaryButton(
            label: 'Walk alone for now',
            leading: Icons.directions_walk,
            onPressed: p.authLoading ? null : p.advance,
          ),
        ],
      ),
    );
  }

  // ── Step 2 · Vessel ─────────────────────────────────────────────────────────────
  Widget _vessel() {
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TdeeHeading(
              'About you', 'The basics behind your calorie math.'),
          BodyStatsForm(
            weightCtrl: _weightCtrl,
            heightCtrl: _heightCtrl,
            ageCtrl: _ageCtrl,
            sex: p.sex,
            onSexChanged: (v) {
              _syncBodyFromControllers();
              p.setBody(sex: v);
            },
          ),
        ],
      ),
      cta: AppPrimaryButton(
        label: 'Continue',
        onPressed: () {
          _syncBodyFromControllers();
          if (_bodyValid) p.advance();
        },
      ),
    );
  }

  // ── Step 3 · Training ─────────────────────────────────────────────────────────
  Widget _training() {
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TdeeHeading('Activity level', 'How active is a typical week?'),
          ActivityLevelSelector(
            selected: p.activityLevel,
            onChanged: p.setActivity,
          ),
        ],
      ),
      cta: AppPrimaryButton(label: 'Continue', onPressed: p.advance),
    );
  }

  // ── Step 4 · Path ────────────────────────────────────────────────────────────
  Widget _path() {
    const goals = <({String value, String label, String desc, IconData icon})>[
      (
        value: 'cut',
        label: 'Cut',
        desc: 'Lose fat · calorie deficit',
        icon: Icons.trending_down
      ),
      (
        value: 'maintain',
        label: 'Maintain',
        desc: 'Hold weight · at TDEE',
        icon: Icons.drag_handle
      ),
      (
        value: 'bulk',
        label: 'Lean gain',
        desc: 'Build muscle · calorie surplus',
        icon: Icons.trending_up
      ),
      (
        value: 'recomp',
        label: 'Recomp',
        desc: 'Trade fat for muscle · at TDEE',
        icon: Icons.sync
      ),
    ];
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TdeeHeading('Your goal', "We'll size your targets around it."),
          for (final g in goals)
            TdeeSelectCard(
              icon: g.icon,
              title: g.label,
              subtitle: g.desc,
              selected: p.goal == g.value,
              onTap: () => p.setGoal(g.value),
            ),
        ],
      ),
      cta: AppPrimaryButton(
        label: 'See my targets',
        onPressed: p.canRevealStats ? p.advance : null,
      ),
    );
  }

  // ── Step 5 · Status Window ─────────────────────────────────────────────────────
  Widget _statusWindow() {
    final theme = Theme.of(context);
    final profile = p.previewProfile;
    if (profile == null) {
      return _stepScaffold(
        body: const TdeeHeading('Your daily targets',
            'Add your body details to see your numbers — or continue and set them later.'),
        cta: Column(
          children: [
            AppPrimaryButton(
                label: 'Add my details', onPressed: () => p.goToStep(2)),
            const SizedBox(height: AppSpacing.sm),
            AppSecondaryButton(label: 'Continue', onPressed: p.advance),
          ],
        ),
      );
    }
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text('Your daily targets',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              children: [
                Text('DAILY TARGET',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1,
                    )),
                const SizedBox(height: AppSpacing.xs),
                TdeeCountUp(
                  value: profile.targetCalories,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -1,
                  ),
                  suffix: ' kcal',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(profile.goalLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: context.appColors.fast,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
                child: TdeeStatTile(label: 'BMR', value: '${profile.bmr}')),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: TdeeStatTile(label: 'TDEE', value: '${profile.tdee}')),
          ]),
          const SizedBox(height: AppSpacing.md),
          Text('SUGGESTED MACROS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1,
              )),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
                child: TdeeMacroTile(
                    label: 'Protein',
                    grams: profile.suggestedProteinG,
                    color: context.appColors.fast)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: TdeeMacroTile(
                    label: 'Carbs',
                    grams: profile.suggestedCarbsG,
                    color: context.appColors.gold)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: TdeeMacroTile(
                    label: 'Fat',
                    grams: profile.suggestedFatG,
                    color: context.appColors.orange)),
          ]),
        ],
      ),
      cta: AppPrimaryButton(
          label: 'Looks right — continue', onPressed: p.advance),
    );
  }

  // ── Step 6 · Protocol ───────────────────────────────────────────────────────
  Widget _protocol() {
    // Non-extended presets first (new-player friendly); extended de-emphasised.
    const protocols = FastingProtocol.all;
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TdeeHeading('Pick a protocol', 'You can change this anytime.'),
          for (final proto in protocols)
            Opacity(
              opacity: proto.isExtended ? 0.6 : 1,
              child: TdeeSelectCard(
                leading: _ProtocolBadge(
                    hours: proto.hours,
                    selected: p.protocolHours == proto.hours),
                title: proto.rpgName,
                subtitle: '${proto.ratio} · ${proto.benefit}',
                selected: p.protocolHours == proto.hours,
                onTap: () => p.setProtocol(proto.hours),
              ),
            ),
        ],
      ),
      cta: AppPrimaryButton(label: 'Continue', onPressed: p.advance),
    );
  }

  // ── Step 7 · Summons ──────────────────────────────────────────────────────────
  Widget _summons() {
    final theme = Theme.of(context);
    final fast = context.appColors.fast;
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: fast.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(Icons.notifications_active, color: fast, size: 32),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Stay on track',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Timely nudges keep your fasts and logs on track — never spam.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SummonRow(
              icon: Icons.flag, text: 'Fast complete & window open'),
          const _SummonRow(icon: Icons.restaurant, text: 'Daily log reminders'),
          const _SummonRow(
              icon: Icons.local_fire_department, text: 'Streak at risk'),
        ],
      ),
      cta: Column(
        children: [
          AppPrimaryButton(
            label: 'Allow notifications',
            onPressed: () async {
              await p.requestNotifications();
              p.advance();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: p.advance, child: const Text('Not now')),
        ],
      ),
    );
  }

  // ── Step 8 · Review ─────────────────────────────────────────────────────────
  Widget _review() {
    final profile = p.previewProfile;
    final proto = FastingProtocol.all.firstWhere(
      (x) => x.hours == p.protocolHours,
      orElse: () => FastingProtocol.all[2],
    );
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TdeeHeading(
              'Review your setup', 'Tap Edit to change anything.'),
          _ReviewRow(
              label: 'Account',
              value: p.identitySummary,
              onEdit: () => p.editStep(1)),
          _ReviewRow(
              label: 'About you',
              value: _bodySummary(),
              onEdit: () => p.editStep(2)),
          _ReviewRow(
              label: 'Activity',
              value: p.activityLevel.label,
              onEdit: () => p.editStep(3)),
          _ReviewRow(
              label: 'Goal',
              value: _goalLabel(p.goal),
              onEdit: () => p.editStep(4)),
          _ReviewRow(
              label: 'Daily target',
              value: profile != null
                  ? '${profile.targetCalories} kcal'
                  : 'Not set',
              onEdit: () => p.editStep(4)),
          _ReviewRow(
              label: 'Protocol',
              value: '${proto.rpgName} · ${proto.ratio}',
              onEdit: () => p.editStep(6)),
        ],
      ),
      cta: AppPrimaryButton(label: 'Confirm & finish', onPressed: p.advance),
    );
  }

  String _bodySummary() {
    final w = p.weightKg, h = p.heightCm, a = p.ageYears;
    if (w == null || h == null || a == null) return 'Not set';
    final sex = p.sex.isEmpty
        ? ''
        : '${p.sex[0].toUpperCase()}${p.sex.substring(1)} · ';
    return '$a yrs · $sex${_trimNum(h)} cm · ${_trimNum(w)} kg';
  }

  static String _goalLabel(String goal) => switch (goal) {
        'cut' => 'Cut',
        'bulk' => 'Lean gain',
        'recomp' => 'Recomp',
        _ => 'Maintain',
      };

  // ── Step 9 · First Quest ───────────────────────────────────────────────────────
  Widget _firstQuest() {
    final theme = Theme.of(context);
    final fast = context.appColors.fast;
    return _stepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fast.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.check_circle, color: fast, size: 40),
          ),
          const SizedBox(height: AppSpacing.md),
          Text("YOU'RE ALL SET",
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              )),
          const SizedBox(height: AppSpacing.xs),
          Text('Begin your first fast',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your profile is set. Start your fast to earn your first XP.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Row(
              children: [
                Icon(Icons.timer_outlined, color: context.appColors.fast),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start your first fast',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_protocolName(p.protocolHours),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      cta: Column(
        children: [
          AppPrimaryButton(
            label: 'Start my first fast',
            leading: Icons.play_arrow,
            onPressed: _completeAndClose,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _completeAndClose,
            child: const Text('Explore the Hub first'),
          ),
        ],
      ),
    );
  }

  String _protocolName(int hours) {
    final proto = FastingProtocol.all.firstWhere(
      (x) => x.hours == hours,
      orElse: () => FastingProtocol.all[2],
    );
    return '${proto.rpgName} · ${proto.ratio}';
  }
}

// ── Top bar (back · progress dots · skip) ──────────────────────────────────────
class _TopBar extends StatelessWidget {
  final int step;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  const _TopBar({
    required this.step,
    required this.showBack,
    required this.onBack,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Dots track the 5 profile steps (Identity..Status).
    final showDots = step >= 1 && step <= 5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: showBack
                ? IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Back',
                  )
                : null,
          ),
          Expanded(
            child: showDots
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final active = i == (step - 1);
                      final done = i < (step - 1);
                      return AnimatedContainer(
                        duration: AppMotion.micro,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 18 : 7,
                        height: 4,
                        decoration: BoxDecoration(
                          color: (active || done)
                              ? context.appColors.fast
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  )
                : const SizedBox.shrink(),
          ),
          SizedBox(
            width: 64,
            height: 48,
            // Per-step skip on the input steps only (Identity … Summons).
            // Awakening has its own bail; Review and First Quest have none.
            child: (step >= 1 && step < OnboardingPresenter.reviewStep)
                ? TextButton(
                    onPressed: onSkip,
                    child: Text('Skip',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant)),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

// ── Review row (label · value · Edit) ──────────────────────────────────────────
class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onEdit;
  const _ReviewRow(
      {required this.label, required this.value, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.sm, 10),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit')),
        ],
      ),
    );
  }
}

// ── Info banner (guest-mode / welcome-back notes) ──────────────────────────────
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                )),
          ),
        ],
      ),
    );
  }
}

class _ProtocolBadge extends StatelessWidget {
  final int hours;
  final bool selected;
  const _ProtocolBadge({required this.hours, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fast = context.appColors.fast;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: selected ? fast : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Text('${hours}h',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
          )),
    );
  }
}

class _SummonRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SummonRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.appColors.fast, size: 18),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
