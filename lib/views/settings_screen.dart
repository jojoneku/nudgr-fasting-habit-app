import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../presenters/ai_coach_presenter.dart';
import '../presenters/auth_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/sync_presenter.dart';
import '../presenters/update_presenter.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../utils/app_spacing.dart';
import 'auth/login_view.dart';
import 'settings/notification_settings_sheet.dart';
import 'stats_view.dart';
import 'widgets/system/system.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.fastingPresenter,
    required this.authPresenter,
    required this.settingsPresenter,
    this.syncPresenter,
    this.nutritionPresenter,
    this.statsPresenter,
    this.aiCoachPresenter,
    this.updatePresenter,
    this.storageService,
    this.notificationService,
  });

  final FastingPresenter fastingPresenter;
  final AuthPresenter authPresenter;
  final SettingsPresenter settingsPresenter;
  final SyncPresenter? syncPresenter;
  final NutritionPresenter? nutritionPresenter;
  final StatsPresenter? statsPresenter;
  final AiCoachPresenter? aiCoachPresenter;
  final UpdatePresenter? updatePresenter;
  final StorageService? storageService;
  final NotificationService? notificationService;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold.large(
      title: 'Settings',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xl,
            ),
            child: ListenableBuilder(
              listenable: Listenable.merge([
                authPresenter,
                settingsPresenter,
                if (nutritionPresenter != null) nutritionPresenter!,
                if (statsPresenter != null) statsPresenter!,
                if (updatePresenter != null) updatePresenter!,
              ]),
              builder: (context, _) => AppGroupedList(
                sections: [
                  _accountGroupSection(context),
                  if (authPresenter.isSignedIn) _cloudAiSection(context),
                  if (nutritionPresenter != null) _foodLearningSection(context),
                  _dataSection(context),
                  _aboutSection(context),
                  if (kDebugMode) _developerSection(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  AppGroupedListSection _accountGroupSection(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    // Account
    if (authPresenter.isSignedIn) {
      final email = authPresenter.userEmail ?? 'Signed in';
      final avatarUrl = authPresenter.userAvatarUrl;
      children.addAll([
        AppListTile(
          insetGrouped: true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Icon(Icons.person, color: theme.colorScheme.primary, size: 18)
                : null,
          ),
          title: Text(email),
          trailing: Icon(
            Icons.check_circle,
            color: theme.colorScheme.tertiary,
            size: 16,
          ),
        ),
        if (syncPresenter != null)
          ListenableBuilder(
            listenable: syncPresenter!,
            builder: (context, _) => AppListTile(
              insetGrouped: true,
              leading: syncPresenter!.isSyncing
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : const AppIconBadge(icon: Icons.sync),
              title: Text(syncPresenter!.statusLabel),
              trailing: TextButton(
                onPressed: syncPresenter!.isSyncing
                    ? null
                    : () async {
                        try {
                          await syncPresenter!.forceSync();
                        } catch (e) {
                          if (context.mounted) {
                            AppToast.error(context, 'Sync failed: $e');
                          }
                        }
                      },
                child: const Text('Sync Now'),
              ),
            ),
          ),
        AppListTile(
          insetGrouped: true,
          leading: AppIconBadge(
            icon: Icons.logout,
            color: theme.colorScheme.error,
          ),
          title: Text(
            'Sign Out',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          onTap: () async {
            final confirm = await AppConfirmDialog.confirm(
              context: context,
              title: 'Sign Out',
              body: 'Your local data stays safe on this device.',
              confirmLabel: 'Sign Out',
              isDestructive: true,
            );
            if (confirm) await authPresenter.signOut();
          },
        ),
      ]);
    } else {
      children.add(AppListTile(
        insetGrouped: true,
        leading: const AppIconBadge(icon: Icons.cloud_outlined),
        title: const Text('Cloud Sync'),
        subtitle: const Text('Sign in to back up and sync'),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => LoginView.show(context, authPresenter),
      ));
    }

    // Profile
    if (statsPresenter != null) {
      final stats = statsPresenter!.stats;
      children.add(AppListTile(
        insetGrouped: true,
        leading: AppIconBadge(
          icon: Icons.shield_outlined,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Character'),
        subtitle: Text('Level ${stats.level} · ${stats.currentXp} XP'),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: StatsView(
                presenter: statsPresenter!,
                fastingPresenter: fastingPresenter,
                authPresenter: authPresenter,
                syncPresenter: syncPresenter,
                settingsPresenter: settingsPresenter,
                aiCoachPresenter: aiCoachPresenter,
              ),
            ),
          ),
        ),
      ));
    }

    // Notification preferences
    if (storageService != null) {
      children.add(AppListTile(
        insetGrouped: true,
        leading: const AppIconBadge(icon: Icons.notifications_outlined),
        title: const Text('Notification preferences'),
        subtitle: const Text('Level-up, weight reminder, finance alerts'),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => showNotificationSettingsSheet(
          context,
          storage: storageService!,
          notifications: notificationService ?? NotificationService(),
        ),
      ));
    }

    // Appearance
    children.add(Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      child: Row(
        children: [
          const AppIconBadge(icon: Icons.palette_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Theme', style: theme.textTheme.bodyLarge),
          ),
          AppSegmentedControl<ThemeMode>(
            selected: settingsPresenter.themeMode,
            onChanged: (mode) {
              settingsPresenter.setThemeMode(mode);
            },
            segments: const [
              (value: ThemeMode.system, label: 'Auto', icon: null),
              (value: ThemeMode.light, label: 'Light', icon: null),
              (value: ThemeMode.dark, label: 'Dark', icon: null),
            ],
          ),
        ],
      ),
    ));

    return AppGroupedListSection(
      title: 'Account',
      footer: 'Theme follows your device by default.',
      children: children,
    );
  }

  AppGroupedListSection _cloudAiSection(BuildContext context) {
    final theme = Theme.of(context);
    return AppGroupedListSection(
      title: 'Cloud AI',
      footer: 'When on, Claude Haiku parses your food log in one call — '
          'reading the local food DB as context to resolve items '
          '(including out-of-DB foods with estimated macros). '
          'Disable to use on-device AI only.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              AppIconBadge(
                icon: Icons.cloud_outlined,
                color: settingsPresenter.useCloudAi
                    ? theme.colorScheme.primary
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cloud AI Coach', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      'Claude Haiku via AWS Bedrock — '
                      'primary food parser when signed in.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: settingsPresenter.useCloudAi,
                onChanged: settingsPresenter.setUseCloudAi,
              ),
            ],
          ),
        ),
      ],
    );
  }

  AppGroupedListSection _foodLearningSection(BuildContext context) {
    final theme = Theme.of(context);
    final p = nutritionPresenter!;
    return AppGroupedListSection(
      title: 'Food learning',
      footer: 'Foods you log confidently are saved here for instant lookup '
          'next time. If a wrong food got stuck (e.g. typing "rice" returns '
          'a rice dessert), reset to clear and start fresh.',
      children: [
        ListenableBuilder(
          listenable: p,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                const AppIconBadge(icon: Icons.menu_book_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Learned foods', style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(
                        '${p.learnedFoodCount} saved',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: p.learnedFoodCount == 0
                      ? null
                      : () => _confirmReset(context, p),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(
      BuildContext context, NutritionPresenter presenter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset learned foods?'),
        content: Text(
          'This clears all ${presenter.learnedFoodCount} saved foods. '
          'Next time you log them, the AI will resolve from scratch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await presenter.clearLearnedFoods();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Learned foods reset.')),
        );
      }
    }
  }

  AppGroupedListSection _dataSection(BuildContext context) {
    final theme = Theme.of(context);
    return AppGroupedListSection(
      title: 'Data',
      children: [
        AppListTile(
          insetGrouped: true,
          leading: const AppIconBadge(icon: Icons.upload_file),
          title: const Text('Export Data'),
          subtitle: const Text('Copy data to clipboard'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () async {
            final data = await fastingPresenter.exportData();
            if (!context.mounted) return;
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Export Data'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Copy this code and save it somewhere safe:'),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black12,
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: SingleChildScrollView(
                        child: Text(
                          data,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy to Clipboard'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: data));
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        AppToast.success(context, 'Data copied to clipboard');
                      }
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        ),
        AppListTile(
          insetGrouped: true,
          leading: AppIconBadge(
            icon: Icons.download,
            color: theme.colorScheme.tertiary,
          ),
          title: const Text('Import Data'),
          subtitle: const Text('Restore from clipboard / code'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () async {
            final controller = TextEditingController();
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Import Data'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                        'Paste your data code here. WARNING: This will overwrite current data!'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Paste data here...',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste'),
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        controller.text = data!.text!;
                      }
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (controller.text.isEmpty) return;
                      try {
                        await fastingPresenter.importData(controller.text);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          AppToast.success(
                              context, 'Data imported successfully');
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          AppToast.error(ctx, 'Import failed: $e');
                        }
                      }
                    },
                    child: const Text('Import'),
                  ),
                ],
              ),
            );
          },
        ),
        AppListTile(
          insetGrouped: true,
          leading: AppIconBadge(
            icon: Icons.delete_forever,
            color: theme.colorScheme.error,
          ),
          title: Text(
            'Clear All Data',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: const Text('Delete all fasting history and quests'),
          onTap: () async {
            final confirm = await AppConfirmDialog.confirm(
              context: context,
              title: 'Clear All Data',
              body:
                  'This will delete ALL your data including fasting history and quests. This cannot be undone.',
              confirmLabel: 'Delete All',
              isDestructive: true,
            );
            if (confirm) {
              await fastingPresenter.clearAllData();
              if (context.mounted) {
                AppToast.success(context, 'All data cleared');
              }
            }
          },
        ),
      ],
    );
  }

  AppGroupedListSection _aboutSection(BuildContext context) {
    final theme = Theme.of(context);
    final up = updatePresenter;
    final version = up?.currentVersion ?? '—';
    final remoteVersion = up?.latestManifest?.version;
    final hasUpdate = up?.updateAvailable ?? false;
    final apkUrl = up?.latestManifest?.apkUrl;

    return AppGroupedListSection(
      title: 'About',
      children: [
        AppListTile(
          insetGrouped: true,
          leading: const AppIconBadge(icon: Icons.info_outline),
          title: const Text('Version'),
          subtitle: Text(
            hasUpdate && remoteVersion != null
                ? '$version · update to $remoteVersion available'
                : version,
          ),
          trailing: hasUpdate
              ? FilledButton.tonal(
                  onPressed: apkUrl == null
                      ? null
                      : () async {
                          final ok = await launchUrl(
                            Uri.parse(apkUrl),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!context.mounted) return;
                          if (ok) {
                            AppToast.success(
                                context, 'Opening download in browser…');
                          } else {
                            AppToast.error(
                                context, 'Could not open the update link.');
                          }
                        },
                  child: const Text('Update'),
                )
              : (up?.isChecking ?? false)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: up == null
                          ? null
                          : () async {
                              await up.checkForUpdates();
                              if (!context.mounted) return;
                              if (!up.updateAvailable) {
                                AppToast.show(
                                    context, 'You’re on the latest version.');
                              }
                            },
                      child: const Text('Check'),
                    ),
        ),
        if (hasUpdate)
          AppListTile(
            insetGrouped: true,
            leading: AppIconBadge(
              icon: Icons.system_update,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              'Update available',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
            subtitle: Text(
              up?.latestManifest?.releaseNotes.isNotEmpty == true
                  ? up!.latestManifest!.releaseNotes
                  : 'Tap Update to download the latest APK.',
            ),
          ),
      ],
    );
  }

  AppGroupedListSection _developerSection(BuildContext context) {
    return AppGroupedListSection(
      title: 'Developer',
      children: [
        AppListTile(
          insetGrouped: true,
          leading: const AppIconBadge(icon: Icons.science),
          title: const Text('Add Test Data'),
          subtitle: const Text('Add sample fasting records'),
          onTap: () {
            fastingPresenter.addTestData();
            AppToast.success(context, 'Test data added');
          },
        ),
        AppListTile(
          insetGrouped: true,
          leading: const AppIconBadge(icon: Icons.notifications_active),
          title: const Text('Test Notification'),
          subtitle: const Text('Check if notifications work'),
          onTap: () async {
            await fastingPresenter.testNotification();
            if (context.mounted) {
              AppToast.show(context, 'Notification sent! Check status bar.');
            }
          },
        ),
      ],
    );
  }
}
