# Widget Testing Guide

Comprehensive patterns for testing Flutter widgets.

## Essential Setup

### Always Set Screen Size

```dart
testWidgets('Test description', (tester) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1.0;
  // Your test code
});
```

### Create Test Widget Wrapper

```dart
Widget createTestWidget(FastingPresenter presenter) => ListenableBuilder(
  listenable: presenter,
  builder: (context, _) => MaterialApp(home: FastingView(presenter: presenter)),
);
```

## Finding Widgets with Keys

### Add Keys to Source Widgets

```dart
// ❌ BAD
ElevatedButton(onPressed: () {}, child: const Text('Start Fast'));

// ✅ GOOD
ElevatedButton(
  key: const Key('startFastButton'),
  onPressed: () {},
  child: const Text('Start Fast'),
);
```

### Use Keys in Tests

```dart
await tester.tap(find.byKey(const Key('startFastButton')));
await tester.pumpAndSettle();
verify(mockPresenter.startFast()).called(1);
```

## Async Widget Testing

### Testing Loading States

```dart
testWidgets('Shows loading during async operation', (tester) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1.0;

  final completer = Completer<void>();
  when(mockPresenter.startFast()).thenAnswer((_) => completer.future);

  await tester.pumpWidget(createTestWidget(mockPresenter));
  await tester.tap(find.byKey(const Key('startFastButton')));
  await tester.pump();

  expect(find.byType(CircularProgressIndicator), findsOneWidget);

  completer.complete();
  await tester.pump();

  expect(find.byType(CircularProgressIndicator), findsNothing);
});
```

### pump vs pumpAndSettle

- `pump()` — advances one frame
- `pumpAndSettle()` — waits for all animations/async to complete

## Platform-Specific Testing

```dart
testWidgets('iOS specific widget shown', (tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

  await tester.pumpWidget(createTestWidget(presenter));

  expect(find.byType(CupertinoButton), findsOneWidget);

  debugDefaultTargetPlatformOverride = null; // Always reset!
});
```

## Widget Testing Checklist

- [ ] Screen size set (1000x1000, DPR 1.0)
- [ ] Keys added to source widgets
- [ ] Keys used in `find.byKey()` calls
- [ ] Both `pump()` and `pumpAndSettle()` used appropriately
- [ ] Loading states tested
- [ ] Error states tested
- [ ] Platform overrides reset (`debugDefaultTargetPlatformOverride = null`)
- [ ] Widget interactions verified with `verify()`
