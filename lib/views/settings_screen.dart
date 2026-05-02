import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presenters/auth_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/sync_presenter.dart';
import '../utils/app_spacing.dart';
import 'auth/login_view.dart';
import 'widgets/system/system.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.fastingPresenter,
    required this.authPresenter,
    required this.settingsPresenter,
    this.syncPresenter,
  });

  final FastingPresenter fastingPresenter;
  final AuthPresenter authPresenter;
  final SettingsPresenter settingsPresenter;
  final SyncPresenter? syncPresenter;

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
              listenable: Listenable.merge([authPresenter, settingsPresenter]),
              builder: (context, _) => AppGroupedList(
                sections: [
                  _appearanceSection(context),
                  _accountSection(context),
                  _dataSection(context),
                  if (kDebugMode) _developerSection(context),
                  _aboutSection(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  AppGroupedListSection _appearanceSection(BuildContext context) {
    final theme = Theme.of(context);
    return AppGroupedListSection(
      title: 'Appearance',
      footer: 'Theme follows your device by default.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            children: [
              const AppIconBadge(
                icon: Icons.palette_outlined,
                size: 36,
                iconSize: 18,
              ),
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
        ),
      ],
    );
  }

  AppGroupedListSection _accountSection(BuildContext context) {
    if (authPresenter.isSignedIn) {
      return _signedInAccountSection(context);
    }
    return _signedOutAccountSection(context);
  }

  AppGroupedListSection _signedOutAccountSection(BuildContext context) {
    return AppGroupedListSection(
      title: 'Account',
      children: [
        AppListTile(
          insetGrouped: true,
          leading: const AppIconBadge(icon: Icons.cloud_outlined),
          title: const Text('Cloud Sync'),
          subtitle: const Text('Sign in to back up and sync'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => LoginView.show(context, authPresenter),
        ),
      ],
    );
  }

  AppGroupedListSection _signedInAccountSection(BuildContext context) {
    final theme = Theme.of(context);
    final email = authPresenter.userEmail ?? 'Signed in';
    final avatarUrl = authPresenter.userAvatarUrl;

    return AppGroupedListSection(
      title: 'Account',
      children: [
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
                      width: 36,
                      height: 36,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : const AppIconBadge(
                      icon: Icons.sync,
                      size: 36,
                      iconSize: 18,
                    ),
              title: Text(syncPresenter!.statusLabel),
              trailing: TextButton(
                onPressed:
                    syncPresenter!.isSyncing ? null : syncPresenter!.forceSync,
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
      ],
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

  AppGroupedListSection _aboutSection(BuildContext context) {
    return AppGroupedListSection(
      title: 'About',
      children: [
        AppListTile(
          insetGrouped: true,
          leading: const AppIconBadge(icon: Icons.description),
          title: const Text('Licenses'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => showLicensePage(context: context),
        ),
      ],
    );
  }
}
