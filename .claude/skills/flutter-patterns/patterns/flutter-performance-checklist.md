# Flutter Performance Checklist

Pre-deployment checklist to ensure optimal app performance.

## Build Configuration

- [ ] Using `flutter build --release` (not debug)
- [ ] ProGuard/R8 enabled for Android (`minifyEnabled true`)
- [ ] No `print()` statements — use `debugPrint` or logger with levels
- [ ] `kDebugMode` guards around debug-only code

```dart
// ❌ Bad
print('Debug message');

// ✅ Good
if (kDebugMode) debugPrint('Debug message');
```

## Widget Performance

### Const Constructors

```dart
// ❌ Bad
Text('Static text')
Icon(Icons.home)
Padding(padding: EdgeInsets.all(16))

// ✅ Good
const Text('Static text')
const Icon(Icons.home)
const Padding(padding: EdgeInsets.all(16))
```

### List Performance

```dart
// ✅ Use ListView.builder, not ListView with children
ListView.builder(
  itemExtent: 60, // Fixed height optimization
  itemCount: items.length,
  itemBuilder: (context, index) {
    return RepaintBoundary(
      key: ValueKey(items[index].id),
      child: ItemWidget(items[index]),
    );
  },
)
```

### Extract Widgets (not functions)

```dart
// ❌ Bad - Function (no const optimization, always rebuilds)
Widget _buildHeader() => Container(child: Text('Header'));

// ✅ Good - Widget class (can be const, cached)
class Header extends StatelessWidget {
  const Header();
  @override
  Widget build(BuildContext context) => const Text('Header');
}
```

## State Management Performance

### Scope ListenableBuilder Narrowly

```dart
// ❌ Bad - rebuilds entire screen
ListenableBuilder(
  listenable: presenter,
  builder: (context, _) => Scaffold(body: Column(children: [
    Text(presenter.time),      // only this changes
    const HeavyStaticWidget(), // doesn't need to rebuild
  ])),
)

// ✅ Good - rebuild only what changes
Scaffold(body: Column(children: [
  ListenableBuilder(
    listenable: presenter,
    builder: (context, _) => Text(presenter.time),
  ),
  const HeavyStaticWidget(),
]))
```

## Heavy Computation

```dart
// ✅ Dart 3 — use Isolate.run() for heavy work
Future<List<FastRecord>> filterRecords(List<FastRecord> records) async {
  return await Isolate.run(() => records.where((r) => r.isComplete).toList());
}
```

## Animation Performance

- [ ] Animations run at 60fps (frame time < 16ms)
- [ ] `RepaintBoundary` wrapping complex animated subtrees
- [ ] `AnimationController` disposed in `dispose()`
- [ ] Prefer `Transform` over layout-based animations

```dart
// ✅ Isolate animated subtree
RepaintBoundary(
  child: AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Transform.rotate(
      angle: _controller.value * 2 * pi,
      child: child,
    ),
    child: const SwordIcon(),
  ),
)
```

## Memory Management

```dart
// ✅ Always dispose controllers and cancel subscriptions
@override
void dispose() {
  _controller.dispose();
  _subscription.cancel();
  super.dispose();
}
```

## Image Optimization

```dart
// ✅ Limit decode size to display size
Image.network(
  imageUrl,
  cacheWidth: 300,
  cacheHeight: 300,
  fit: BoxFit.cover,
)
```

## Impeller (Modern Renderer)

Impeller is the default renderer on iOS (Flutter 3.16+) and Android (Flutter 3.22+).

- No shader compilation jank — Impeller pre-compiles all shaders
- `--trace-skia` no longer needed
- `RepaintBoundary` still valuable for isolating animated subtrees

## Performance Metrics

| Metric | Target |
| --- | --- |
| Cold start | < 3 seconds |
| Frame rendering | < 16ms (60fps) |
| Scrolling | Smooth at 60fps |
| Animations | ≤ 400ms (The System max) |

## Quick Wins (Top 10)

1. Add `const` everywhere possible
2. Use `ListView.builder` not `ListView(children:)`
3. Scope `ListenableBuilder` as narrow as possible
4. Move heavy computation to `Isolate.run()`
5. Add `RepaintBoundary` to expensive widgets
6. Use `AnimatedBuilder` for animations
7. Set `cacheWidth/cacheHeight` on images
8. Dispose all controllers and subscriptions
9. Extract `StatelessWidget` classes (not functions)
10. Test on physical devices, not simulators
