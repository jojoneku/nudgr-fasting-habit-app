import 'package:flutter/material.dart';

/// A dashboard section's header link ("View full", "View all") with a
/// 44×44 touch target.
class DashboardHeaderLink extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const DashboardHeaderLink({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: cs.primary,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 16),
        ],
      ),
    );
  }
}
