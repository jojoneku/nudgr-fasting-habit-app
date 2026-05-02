import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../../utils/app_spacing.dart';
import '../../../../utils/app_text_styles.dart';

/// Spinner + label loading state, or a Skeletonizer wrap of any widget tree.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.message});

  /// Wrap [child] in a shimmer skeleton. Toggle [enabled] to swap real content.
  const factory AppLoadingState.skeleton({
    Key? key,
    required Widget child,
    bool enabled,
  }) = _AppSkeletonState;

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(message!,
                  style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppSkeletonState extends AppLoadingState {
  const _AppSkeletonState({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(enabled: enabled, child: child);
  }
}
