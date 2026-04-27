import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../presenters/auth_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../app_colors.dart';
import 'auth/login_view.dart';

class SettingsScreen extends StatelessWidget {
  final FastingPresenter fastingPresenter;
  final AuthPresenter authPresenter;

  const SettingsScreen({
    super.key,
    required this.fastingPresenter,
    required this.authPresenter,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListenableBuilder(
        listenable: authPresenter,
        builder: (context, _) => ListView(
          children: [
            _CloudSyncSection(authPresenter: authPresenter),
            const Divider(),
          ListTile(
            leading: const Icon(Icons.science, color: AppColors.primary),
            title: const Text('Add Test Data'),
            subtitle: const Text('Add sample fasting records'),
            onTap: () {
              fastingPresenter.addTestData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Added test data!')),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active,
                color: AppColors.secondary),
            title: const Text('Test Notification'),
            subtitle: const Text('Check if notifications work'),
            onTap: () async {
              await fastingPresenter.testNotification();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Notification sent! Check status bar.')),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_file, color: AppColors.primary),
            title: const Text('Export Data'),
            subtitle: const Text('Copy data to clipboard'),
            onTap: () async {
              final data = await fastingPresenter.exportData();
              if (context.mounted) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Export Data'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                            'Copy this code and save it somewhere safe:'),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.black12,
                          constraints: const BoxConstraints(maxHeight: 150),
                          child: SingleChildScrollView(
                            child: Text(data,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 10)),
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
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Data copied to clipboard!')),
                            );
                          }
                        },
                      ),
                      TextButton(
                        child: const Text('Close'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download, color: AppColors.success),
            title: const Text('Import Data'),
            subtitle: const Text('Restore from clipboard/code'),
            onTap: () async {
              final controller = TextEditingController();
              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
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
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    TextButton(
                      child: const Text('Import'),
                      onPressed: () async {
                        if (controller.text.isEmpty) return;
                        try {
                          await fastingPresenter.importData(controller.text);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Data imported successfully!')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Import failed: $e'),
                                  backgroundColor: AppColors.danger),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: AppColors.neutral),
            title: const Text('Clear All Data'),
            subtitle: const Text('Delete all fasting history and quests'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Confirm Reset'),
                  content: const Text(
                      'This will delete ALL your data including fasting history and quests. This cannot be undone!'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.neutral),
                      child: const Text('Delete All'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await fastingPresenter.clearAllData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('All data cleared successfully')),
                  );
                }
              }
            },
          ),
        ],
        ),
      ),
    );
  }
}

// ── Cloud Sync Section ────────────────────────────────────────────────────────

class _CloudSyncSection extends StatelessWidget {
  final AuthPresenter authPresenter;

  const _CloudSyncSection({required this.authPresenter});

  @override
  Widget build(BuildContext context) {
    if (authPresenter.isSignedIn) {
      return _SignedInTile(authPresenter: authPresenter);
    }
    return _SignInTile(authPresenter: authPresenter);
  }
}

class _SignInTile extends StatelessWidget {
  final AuthPresenter authPresenter;

  const _SignInTile({required this.authPresenter});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cloud_outlined, color: AppColors.primary),
      title: const Text('Cloud Sync'),
      subtitle: const Text('Sign in to back up and sync your data'),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textSecondary, size: 18),
      onTap: () => LoginView.show(context, authPresenter),
    );
  }
}

class _SignedInTile extends StatelessWidget {
  final AuthPresenter authPresenter;

  const _SignedInTile({required this.authPresenter});

  @override
  Widget build(BuildContext context) {
    final email = authPresenter.userEmail ?? 'Signed in';
    final avatarUrl = authPresenter.userAvatarUrl;

    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage:
                avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? const Icon(Icons.person, color: AppColors.primary, size: 18)
                : null,
          ),
          title: const Text('Cloud Sync',
              style: TextStyle(color: AppColors.textPrimary)),
          subtitle: Text(email,
              style: const TextStyle(
                  color: AppColors.success, fontSize: 12)),
          trailing: const Icon(Icons.check_circle,
              color: AppColors.success, size: 16),
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: AppColors.danger),
          title: const Text('Sign Out',
              style: TextStyle(color: AppColors.danger)),
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Sign Out'),
                content:
                    const Text('Your local data stays safe on this device.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            );
            if (confirm == true) await authPresenter.signOut();
          },
        ),
      ],
    );
  }
}
