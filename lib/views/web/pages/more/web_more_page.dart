import 'package:flutter/material.dart';

import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/auth_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/web/pages/setup/web_setup_page.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/widgets/ai_chat_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The narrow-web "More" tab.
///
/// Below the desktop breakpoint the browser renders the mobile Treasury module
/// instead of the sidebar shell — and the sidebar is the only place the web
/// build puts the signed-in account, sign-out, the light/dark toggle, the
/// Nudgy and Setup & Accounts. Without this page a mobile-web user could not
/// sign out at all, and until Plan 063 Phase 1 could not reach Setup either.
/// Everything here is a narrow-viewport mirror of the sidebar, nothing new.
class WebMorePage extends StatelessWidget {
  final AuthPresenter authPresenter;
  final AiCoachPresenter advisorPresenter;

  /// For the Setup & Accounts page this tab pushes — the same presenters the
  /// desktop rail's Setup destination builds it with.
  final TreasuryDashboardPresenter dashPresenter;
  final LedgerPresenter ledgerPresenter;

  /// Current theme mode and its toggle, threaded from the web app root.
  final bool isDark;
  final VoidCallback onToggleTheme;

  const WebMorePage({
    super.key,
    required this.authPresenter,
    required this.advisorPresenter,
    required this.dashPresenter,
    required this.ledgerPresenter,
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

  void _openSetup(BuildContext context) {
    // Setup's data is reloaded on entry the way the desktop rail does it:
    // accounts live on the dashboard presenter, categories on the ledger's.
    dashPresenter.load();
    ledgerPresenter.load();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SetupRoute(
          dashPresenter: dashPresenter,
          ledgerPresenter: ledgerPresenter,
        ),
      ),
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
                title: 'Treasury',
                child: AppCard(
                  variant: AppCardVariant.elevated,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    key: WebKeys.moreSetup,
                    minTileHeight: 56,
                    leading: Icon(Icons.settings_outlined,
                        color: cs.onSurfaceVariant),
                    title: const Text('Setup & Accounts'),
                    subtitle: Text(
                      'Accounts, credit lines and categories',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    trailing:
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    onTap: () => _openSetup(context),
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

/// Setup & Accounts as a pushed route for the narrow layout: the desktop page
/// under an app bar with a back button, since there is no rail to return by.
class _SetupRoute extends StatelessWidget {
  final TreasuryDashboardPresenter dashPresenter;
  final LedgerPresenter ledgerPresenter;

  const _SetupRoute({
    required this.dashPresenter,
    required this.ledgerPresenter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text(
          'SETUP & ACCOUNTS',
          style: theme.textTheme.titleSmall?.copyWith(letterSpacing: 2.0),
        ),
        centerTitle: true,
      ),
      body: WebSetupPage(
        presenter: dashPresenter,
        ledgerPresenter: ledgerPresenter,
      ),
    );
  }
}
