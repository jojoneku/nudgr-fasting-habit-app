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
import '../utils/app_spacing.dart';
import 'auth/login_view.dart';
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
  });

  final FastingPresenter fastingPresenter;
  final AuthPresenter authPresenter;
  final SettingsPresenter settingsPresenter;
  final SyncPresenter? syncPresenter;
  final NutritionPresenter? nutritionPresenter;
  final StatsPresenter? statsPresenter;
  final AiCoachPresenter? aiCoachPresenter;
  final UpdatePresenter? updatePresenter;

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
                  if (nutritionPresenter?.isFoodSearchAvailable ?? false)
                    _smartSearchSection(context),
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

  AppGroupedListSection _smartSearchSection(BuildContext context) {
    final theme = Theme.of(context);
    final p = nutritionPresenter!;
    final status = p.foodSearchStatus;
    final progress = p.foodIndexProgress;
    final bundling = p.isAiBundleDownloading;

    // Bundle download takes priority over single-component states.
    if (bundling) {
      return AppGroupedListSection(
        title: 'AI Models',
        footer:
            'Smart search lights up after step 1. Downloads run sequentially.',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIconBadge(
                      icon: Icons.cloud_download_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.aiBundlePhaseLabel,
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${p.aiBundleProgress}% overall',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: p.aiBundleProgress / 100.0,
                  minHeight: 4,
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Bundle entry point — when neither model is installed, offer one combined action.
    if (p.isAiBundleAvailable) {
      return AppGroupedListSection(
        title: 'AI Models',
        footer:
            'Both models run on-device after install. No cloud, no data leaves your phone.',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                const AppIconBadge(icon: Icons.auto_awesome_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Get the AI bundle',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Smart food search (75 MB) + AI Coach (586 MB). '
                        'Downloads in stages — search works after step 1.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    await p.downloadAiBundle();
                  },
                  child: const Text('Download'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final (
      String title,
      String subtitle,
      IconData icon,
      String? actionLabel,
      VoidCallback? onAction,
    ) info = switch (status) {
      FoodSearchStatus.notInstalled => (
          'Smart food search',
          'Download the embedder to enable semantic search. ${p.foodEmbedderSizeLabel ?? '~75 MB'}.',
          Icons.auto_awesome_outlined,
          'Download',
          () async {
            await p.enableFoodSearch();
          },
        ),
      FoodSearchStatus.downloading => (
          'Downloading smart search…',
          '${p.foodEmbedderDownloadProgress}% • ${p.foodEmbedderName ?? 'Embedder'}',
          Icons.cloud_download_outlined,
          null,
          null,
        ),
      FoodSearchStatus.loading => (
          'Loading smart search…',
          'Initialising the embedder.',
          Icons.hourglass_top,
          null,
          null,
        ),
      FoodSearchStatus.idle => (
          'Smart food search',
          'Embedder ready. Tap to build the food index.',
          Icons.auto_awesome_outlined,
          'Build index',
          () async {
            await p.enableFoodSearch();
          },
        ),
      FoodSearchStatus.indexing => (
          'Indexing food database…',
          '${progress.indexed} / ${progress.total} '
              '(${(progress.fraction * 100).round()}%)',
          Icons.sync,
          null,
          null,
        ),
      FoodSearchStatus.ready => (
          'Smart food search active',
          '${progress.total} foods indexed. Type meals naturally — '
              '"creamy yogurt with berries" works.',
          Icons.auto_awesome,
          'Rebuild',
          () async {
            await p.rebuildFoodIndex();
          },
        ),
      FoodSearchStatus.failed => (
          'Smart search unavailable',
          'Your device does not support the on-device embedder. '
              'Falling back to keyword search.',
          Icons.error_outline,
          null,
          null,
        ),
      FoodSearchStatus.disabled => (
          'Smart search',
          'Not configured.',
          Icons.help_outline,
          null,
          null,
        ),
    };

    return AppGroupedListSection(
      title: 'Smart Food Search',
      footer: 'Powered by an on-device AI. No cloud required after install.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              AppIconBadge(
                icon: info.$3,
                color: status == FoodSearchStatus.ready
                    ? theme.colorScheme.primary
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.$1, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      info.$2,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (status == FoodSearchStatus.downloading)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(
                          value: p.foodEmbedderDownloadProgress / 100.0,
                          minHeight: 3,
                        ),
                      ),
                    if (status == FoodSearchStatus.indexing)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(
                          value: progress.fraction,
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
              ),
              if (info.$4 != null && info.$5 != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: info.$5,
                  child: Text(info.$4!),
                ),
              ],
            ],
          ),
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
