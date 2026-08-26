import 'package:flutter/material.dart';

import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/auth_presenter.dart';
import 'package:intermittent_fasting/views/widgets/ai_chat_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The narrow-web "More" tab.
///
/// Below the desktop breakpoint the browser renders the mobile Treasury module
/// instead of the sidebar shell — and the sidebar is the only place the web
/// build puts the signed-in account, sign-out, the light/dark toggle and the
/// Nudgy. Without this page a mobile-web user could not sign out at all.
/// Everything here is a narrow-viewport mirror of the sidebar, nothing new.
class WebMorePage extends StatelessWidget {
  final AuthPresenter authPresenter;
  final AiCoachPresenter advisorPresenter;

  /// Current theme mode and its toggle, threaded from the web app root.
  final bool isDark;
  final VoidCallback onToggleTheme;

  const WebMorePage({
    super.key,
    required this.authPresenter,
    required this.advisorPresenter,
    required this.isDark,
    required this.onToggleTheme,
  });

  void _openAdvisor(BuildContext context) {
    AiChatSheet.show(
      context,
      presenter: advisorPresenter,
      entryPoint: AiCoachEntryPoint.financeAdvisor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: authPresenter,
      builder: (context, _) {
        final email = authPresenter.userEmail;
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            title: Text(
              'MORE',
              style: theme.textTheme.titleSmall?.copyWith(letterSpacing: 2.0),
            ),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              AppSection(
                title: 'Nudgy',
                child: AppCard(
                  variant: AppCardVariant.elevated,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ask about your bills, budgets and spending.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _openAdvisor(context),
                        icon: const Icon(Icons.savings_outlined, size: 18),
                        label: const Text('Open Nudgy'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppSection(
                title: 'Appearance',
                child: AppCard(
                  variant: AppCardVariant.elevated,
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    value: isDark,
                    onChanged: (_) => onToggleTheme(),
                    title: const Text('Dark mode'),
                    secondary: Icon(
                      isDark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppSection(
                title: 'Account',
                child: AppCard(
                  variant: AppCardVariant.elevated,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (email != null) ...[
                        Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                email,
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: authPresenter.signOut,
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Sign out'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
