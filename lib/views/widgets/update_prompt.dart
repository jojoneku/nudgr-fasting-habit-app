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
  bool _busy = false;

  UpdatePresenter get _presenter => widget.presenter;

  Future<void> _onDownloadTap() async {
    if (_busy) return;
    if (_presenter.canSelfUpdate) {
      // Fire-and-forget: progress streams into the card via the presenter.
      _presenter.downloadUpdate();
      return;
    }
    // Non-Android fallback: open the release URL externally.
    final apkUrl = _presenter.latestManifest?.apkUrl;
    if (apkUrl == null) return;
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onInstallTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await _presenter.installUpdate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      AppToast.error(context, 'Could not open installer: $error');
    }
  }

  String _subtitle() {
    final version = _presenter.latestManifest?.version;
    switch (_presenter.state) {
      case UpdateFlowState.downloading:
        final progress = _presenter.downloadProgress;
        return progress == null
            ? 'Downloading…'
            : 'Downloading… ${(progress * 100).round()}%';
      case UpdateFlowState.readyToInstall:
        return version == null
            ? 'Downloaded — ready to install'
            : 'v$version downloaded — ready to install';
      case UpdateFlowState.error:
        return _presenter.errorMessage ?? 'Download failed — retry.';
      default:
        return version == null ? '' : 'Version $version';
    }
  }

  Widget _trailingAction(ThemeData theme) {
    switch (_presenter.state) {
      case UpdateFlowState.downloading:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case UpdateFlowState.readyToInstall:
        return FilledButton.tonal(
          onPressed: _busy ? null : _onInstallTap,
          child: const Text('Install', style: TextStyle(fontSize: 12)),
        );
      case UpdateFlowState.error:
        return FilledButton.tonal(
          onPressed: _busy ? null : _onDownloadTap,
          child: const Text('Retry', style: TextStyle(fontSize: 12)),
        );
      default:
        return FilledButton.tonal(
          onPressed: _busy ? null : _onDownloadTap,
          child: const Text('Update', style: TextStyle(fontSize: 12)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        if (!_presenter.updateAvailable) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final subtitle = _subtitle();
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
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
                                _presenter.readyToInstall
                                    ? 'Update Ready'
                                    : 'Update Available',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _presenter.state ==
                                            UpdateFlowState.error
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _trailingAction(theme),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _presenter.dismissUpdate,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),
                    if (_presenter.isDownloading) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _presenter.downloadProgress,
                          minHeight: 5,
                        ),
                      ),
                    ],
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
