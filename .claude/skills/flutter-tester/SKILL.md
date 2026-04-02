---
name: flutter-tester
description: Use when creating, writing, fixing, or reviewing tests in a Flutter project. Covers unit tests, widget tests, integration tests, and Mockito mocking. Provides Given-When-Then patterns and layer isolation strategies.
compatibility: Requires a Flutter project with flutter_test. Works with Mockito. Run `dart run build_runner build` to generate mocks after adding @GenerateMocks annotations.
metadata:
  source: https://github.com/Harishwarrior/flutter-claude-skills
  author: harish
  version: 1.0.0
---

# Flutter Tester

## Overview

Test each architectural layer in isolation using Given-When-Then structure. Always test both success and error paths. Never mock providers — override their dependencies instead.

## Reference Files

Load the relevant file based on what you're testing:

| What you're testing | Reference file |
| --- | --- |
| Repository, Service, Presenter logic | `references/layer_testing_patterns.md` |
| Widget UI, interactions, dialogs, navigation | `references/widget_testing_guide.md` |

## Core Principles

### 1. Layer Isolation

Test each layer against its own mocked dependencies:

| Layer | What to test | What to mock |
| --- | --- | --- |
| **Model** | `fromJson`/`toJson`, validation | Nothing (pure functions) |
| **Presenter** | State transitions, RPG math, XP calculations | StorageService |
| **Service** | Storage reads/writes | SharedPreferences (via mock StorageService) |
| **Widget** | UI behaviour and interactions | Presenter (via mock) |

### 2. Given-When-Then Structure

```dart
test('Given valid data, When fetchUsers called, Then returns user list', () async {
  // Arrange (Given)
  when(mockStorage.getFastingState()).thenAnswer((_) async => expectedState);

  // Act (When)
  final result = await presenter.loadFastingState();

  // Assert (Then)
  expect(result, equals(expectedState));
  verify(mockStorage.getFastingState()).called(1);
});
```

### 3. Test Organisation

```dart
group('FastingPresenter', () {
  group('startFast', () {
    setUp(() { /* init mocks */ });

    test('Given not fasting, When startFast called, Then sets isFasting = true', () { });
    test('Given already fasting, When startFast called, Then throws StateError', () { });
  });
});
```

## Standard Test Setup

### Generate Mocks

```dart
@GenerateMocks([StorageService, NotificationService])
void main() { ... }
```

Run `dart run build_runner build` after modifying `@GenerateMocks`.

## Quick Reference

| Scenario | Key pattern |
| --- | --- |
| Test a Presenter | Mock StorageService → inject into Presenter constructor |
| Test a Widget | `pumpWidget`, `find.byKey()`, `pumpAndSettle()` |
| Test loading state | Use `Completer`, `pump()` to assert loading, complete, `pump()` again |
| Test RPG math | Pure input/output — no mocks needed |

## Running Tests

```bash
flutter test --coverage                       # All tests with coverage
flutter test test/path/to/test.dart           # Specific file
flutter test --plain-name "Given valid data"  # Filter by name
```

## Common Mistakes

| Mistake | Fix |
| --- | --- |
| Logic in Widget test | Test the Presenter method instead |
| `await Future.delayed()` in tests | Use `await tester.pumpAndSettle()` or `Completer` instead |
| Finding widgets by text string | Use `find.byKey(const Key('name'))` — stable across text changes |
| No screen size in widget tests | Add `tester.view.physicalSize = const Size(1000, 1000)` |
