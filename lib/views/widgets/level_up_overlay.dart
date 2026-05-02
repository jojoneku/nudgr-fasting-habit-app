import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../utils/app_motion.dart';
import 'system/system.dart';

class LevelUpOverlay extends StatefulWidget {
  const LevelUpOverlay({
    super.key,
    required this.newLevel,
    required this.onClose,
  });

  final int newLevel;
  final VoidCallback onClose;

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.modal);
    _fade = CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut);
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: AppMotion.spring));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        alignment: Alignment.center,
        child: ScaleTransition(
          scale: _scale,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Level up!',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 20),
              AppNumberDisplay(
                value: '${widget.newLevel}',
                label: 'You have reached',
                labelPosition: AppNumberLabelPosition.above,
                size: AppNumberSize.headline,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: AppPrimaryButton(
                  label: 'Continue',
                  onPressed: widget.onClose,
                  height: 52,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
