# Flutter Animation Patterns — Quick Reference

## Project Constraints (The System)
- Micro-interactions: **150–300ms**
- Max animation duration: **≤ 400ms**
- Prefer implicit animations when possible

## Implicit Animations (Easiest)

```dart
// AnimatedContainer — size, color, border radius
AnimatedContainer(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeInOut,
  width: _expanded ? 200 : 100,
  decoration: BoxDecoration(
    color: _expanded ? AppColors.accent : AppColors.surface,
    borderRadius: BorderRadius.circular(_expanded ? 50 : 12),
  ),
)

// AnimatedOpacity — fade in/out
AnimatedOpacity(
  opacity: _visible ? 1.0 : 0.0,
  duration: const Duration(milliseconds: 200),
  child: child,
)

// TweenAnimationBuilder — no controller needed
TweenAnimationBuilder<double>(
  tween: Tween(begin: 0.0, end: _isActive ? 1.0 : 0.0),
  duration: const Duration(milliseconds: 300),
  builder: (context, value, child) {
    return Transform.scale(
      scale: 0.8 + (0.2 * value),
      child: Opacity(opacity: value, child: child),
    );
  },
  child: const RPGBadge(),
)
```

## AnimatedSwitcher — swap between states

```dart
AnimatedSwitcher(
  duration: const Duration(milliseconds: 200),
  transitionBuilder: (child, animation) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(scale: animation, child: child),
  ),
  child: _isFasting
      ? const Icon(Icons.timer, key: ValueKey('timer'))
      : const Icon(Icons.play_arrow, key: ValueKey('play')),
  // Key is essential for AnimatedSwitcher to detect changes
)
```

## Explicit Animations (More Control)

### Fade In
```dart
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  const FadeIn({required this.child, this.duration = const Duration(milliseconds: 250)});

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _animation, child: widget.child);
}
```

### Animated Button Press (scale tap feedback)
```dart
class AnimatedButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  const AnimatedButton({required this.onPressed, required this.child});

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 100), vsync: this);
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) { _controller.reverse(); widget.onPressed(); },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
```

## Staggered List Animation
```dart
class AnimatedListItem extends StatefulWidget {
  final Widget child;
  final int index;
  const AnimatedListItem({required this.child, required this.index});

  @override
  State<AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<AnimatedListItem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _controller.forward();
    });
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SlideTransition(
    position: _slide,
    child: FadeTransition(opacity: _fade, child: widget.child),
  );
}
```

## Hero Animation
```dart
// Source screen
Hero(tag: 'fast-timer-${fast.id}', child: TimerWidget(fast))

// Destination screen
Hero(tag: 'fast-timer-${fast.id}', child: LargeTimerWidget(fast))
```

## Page Transitions

### Material 3 Standard Transition
```dart
class M3PageTransition extends PageRouteBuilder {
  final Widget page;
  M3PageTransition({required this.page}) : super(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0.0, 0.03), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeInOutCubicEmphasized)),
          child: child,
        ),
      );
    },
  );
}
```

## Shimmer Loading
```dart
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  const ShimmerLoading({required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(_controller);
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          stops: [_animation.value - 0.3, _animation.value, _animation.value + 0.3],
          colors: [Colors.grey[800]!, Colors.grey[600]!, Colors.grey[800]!],
        ).createShader(bounds),
        child: widget.child,
      ),
    );
  }
}
```

## Performance Tips
- Use `RepaintBoundary` for isolated animated subtrees
- Prefer `Transform` over layout-based animations
- Always `dispose()` controllers in `dispose()`
- Use `SingleTickerProviderStateMixin` for one controller, `TickerProviderStateMixin` for multiple
