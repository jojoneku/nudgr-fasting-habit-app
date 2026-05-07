import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../presenters/update_presenter.dart';
import 'system/overlays/app_toast.dart';

class UpdatePrompt extends StatefulWidget {
  final UpdatePresenter presenter;

  const UpdatePrompt({required this.presenter, super.key});

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  bool _launching = false;

  Future<void> _onUpdateTap(String? apkUrl) async {
    if (apkUrl == null || _launching) return;
    setState(() => _launching = true);
    try {
      final ok = await launchUrl(
        Uri.parse(apkUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (ok) {
        AppToast.success(context, 'Opening download in browser…');
      } else {
        AppToast.error(context, 'Could not open the update link.');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Update failed: $e');
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        if (!widget.presenter.updateAvailable) {
          return const SizedBox.shrink();
        }

        final manifest = widget.presenter.latestManifest;
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: theme.colorScheme.primary, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha:
                            theme.brightness == Brightness.dark ? 0.18 : 0.08,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.system_update,
                        color: theme.colorScheme.primary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Update Available',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          if (manifest != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Version ${manifest.version}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _launching
                          ? null
                          : () => _onUpdateTap(manifest?.apkUrl),
                      child: _launching
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Update',
                              style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: widget.presenter.dismissUpdate,
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
