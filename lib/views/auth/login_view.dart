import 'package:flutter/material.dart';

import '../../presenters/auth_presenter.dart';
import '../../utils/app_spacing.dart';
import '../widgets/system/system.dart';

class LoginView extends StatefulWidget {
  final AuthPresenter presenter;

  const LoginView({super.key, required this.presenter});

  static Future<void> show(BuildContext context, AuthPresenter presenter) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoginView(presenter: presenter),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  @override
  void initState() {
    super.initState();
    widget.presenter.addListener(_onPresenterChange);
  }

  @override
  void dispose() {
    widget.presenter.removeListener(_onPresenterChange);
    super.dispose();
  }

  void _onPresenterChange() {
    if (!mounted) return;
    if (widget.presenter.isSignedIn && !widget.presenter.isLoading) {
      Navigator.of(context).pop();
      return;
    }
    final err = widget.presenter.error;
    if (err != null) {
      AppToast.error(context, err);
      widget.presenter.clearError();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
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
                  'Nudgr',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Text(
                  'Your habits. Your progress. Your rules.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const Spacer(flex: 4),
              AppPrimaryButton(
                label: 'Continue with Google',
                isLoading: widget.presenter.isLoading,
                onPressed: widget.presenter.isLoading
                    ? null
                    : widget.presenter.signInWithGoogle,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Log in later',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
