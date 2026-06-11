import 'package:flutter/material.dart';

import '../../presenters/auth_presenter.dart';
import '../../utils/app_spacing.dart';
import '../widgets/system/system.dart';

/// Signed-out screen for the Treasury web companion (Plan 042). Unlike the
/// mobile [LoginView], this is an always-mounted view the shell swaps in based
/// on auth state — Google sign-in here triggers a full-page OAuth redirect, so
/// there is no "log in later" guest path on web (cloud data is the whole point).
class WebLoginView extends StatelessWidget {
  final AuthPresenter presenter;

  const WebLoginView({super.key, required this.presenter});

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
              final err = presenter.error;
              if (err != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  AppToast.error(context, err);
                  presenter.clearError();
                });
              }
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
