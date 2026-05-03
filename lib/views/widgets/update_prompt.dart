import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../presenters/update_presenter.dart';
import '../../app_colors.dart';

class UpdatePrompt extends StatelessWidget {
  final UpdatePresenter presenter;

  const UpdatePrompt({required this.presenter, super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (!presenter.updateAvailable) {
          return const SizedBox.shrink();
        }

        final manifest = presenter.latestManifest;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.system_update,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Update Available',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (manifest != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Version ${manifest.version}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () async {
                        if (manifest?.apkUrl != null) {
                          if (await canLaunchUrl(Uri.parse(manifest!.apkUrl))) {
                            await launchUrl(
                              Uri.parse(manifest.apkUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        }
                      },
                      child:
                          const Text('Update', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: presenter.dismissUpdate,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
