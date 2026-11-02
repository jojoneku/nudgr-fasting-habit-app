import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// What notification access means, shown before the system page opens.
/// Resolves to true when the user chooses to continue.
Future<bool> showCaptureDisclosureSheet(BuildContext context) async {
  final result = await AppBottomSheet.show<bool>(
    context: context,
    title: 'Read notifications?',
    body: const _DisclosureBody(),
    primaryAction: AppPrimaryButton(
      label: 'Continue to settings',
      onPressed: () => Navigator.of(context).pop(true),
    ),
    secondaryAction: AppSecondaryButton(
      label: 'Not now',
      onPressed: () => Navigator.of(context).pop(false),
    ),
  );
  return result ?? false;
}

class _DisclosureBody extends StatelessWidget {
  const _DisclosureBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(text, style: body)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Nudgr can read the notifications your bank and e-wallet apps post '
          'and turn them into draft transactions for you to review.',
          style: body,
        ),
        const SizedBox(height: AppSpacing.md),
        point(
            Icons.filter_alt_outlined,
            'Only the apps you pick are kept. Every other notification is '
            'dropped the moment it arrives.'),
        point(
            Icons.phone_android_outlined,
            'The text stays on this phone. It goes to the cloud only when '
            'Cloud AI is on, and only for rows the parser could not finish.'),
        point(Icons.check_circle_outline,
            'Nothing is added to your ledger until you tap Approve.'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Android will open the Notification access page next. On Android 13 '
          'and newer, an app installed outside the Play Store may show the '
          'toggle greyed out as a restricted setting. Open App info for Nudgr, '
          'tap the ⋮ menu, choose "Allow restricted settings", then try again.',
          style: muted,
        ),
      ],
    );
  }
}
