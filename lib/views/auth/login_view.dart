import 'package:flutter/material.dart';

import '../../presenters/auth_presenter.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    widget.presenter.addListener(_onPresenterChange);
  }

  @override
  void dispose() {
    widget.presenter.removeListener(_onPresenterChange);
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
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

  bool _validate() {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    final eErr = (email.isEmpty || !email.contains('@'))
        ? 'Enter a valid email'
        : null;
    final pErr = pass.length < 6 ? 'At least 6 characters' : null;
    setState(() {
      _emailError = eErr;
      _passwordError = pErr;
    });
    return eErr == null && pErr == null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppPageScaffold(
      padding: EdgeInsets.zero,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xxl),
            _SystemIcon(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'THE SYSTEM',
              style: AppTextStyles.headlineMedium.copyWith(letterSpacing: 3),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your progress. Your rules.',
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Welcome back', style: AppTextStyles.headlineSmall),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    errorText: _emailError,
                    onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: '••••••••',
                    obscureText: _obscurePassword,
                    focusNode: _passwordFocusNode,
                    textInputAction: TextInputAction.done,
                    errorText: _passwordError,
                    suffixIcon: _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    onSuffixIconTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => AppToast.show(context, 'Coming soon'),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  AppPrimaryButton(
                    label: 'Sign in',
                    onPressed: () {
                      if (_validate()) {
                        AppToast.show(context, 'Email sign-in coming soon');
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm),
                        child: Text(
                          'or',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppSecondaryButton(
                    label: 'Continue with Google',
                    isLoading: widget.presenter.isLoading,
                    onPressed: widget.presenter.isLoading
                        ? null
                        : widget.presenter.signInWithGoogle,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextButton(
              onPressed: () => AppToast.show(context, 'Sign up coming soon'),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: "Don't have an account? ",
                      style: AppTextStyles.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: 'Sign up',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SystemIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.primary, width: 1.5),
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
      ),
      child: Icon(Icons.bolt, color: theme.colorScheme.primary, size: 36),
    );
  }
}
