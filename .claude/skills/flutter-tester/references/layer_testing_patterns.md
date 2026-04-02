# Layer Testing Patterns

This file provides comprehensive examples for testing each architectural layer in Flutter applications.

## Repository / Presenter Layer Testing

Presenters coordinate business logic and state. Test both success and error scenarios.

### Basic Presenter Test Pattern

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([StorageService])
void main() {
  late FastingPresenter presenter;
  late MockStorageService mockStorage;

  setUp(() {
    mockStorage = MockStorageService();
    presenter = FastingPresenter(storage: mockStorage);
  });

  group('FastingPresenter', () {
    group('startFast', () {
      test('Given not fasting, When startFast called, Then isFasting is true', () async {
        // Arrange
        when(mockStorage.saveFastingState(any)).thenAnswer((_) async {});
        when(mockStorage.getFastingState()).thenAnswer((_) async => null);

        // Act
        await presenter.startFast();

        // Assert
        expect(presenter.isFasting, isTrue);
        verify(mockStorage.saveFastingState(any)).called(1);
      });

      test('Given DAO throws, When startFast called, Then isFasting remains false', () async {
        // Arrange
        when(mockStorage.saveFastingState(any)).thenThrow(Exception('Storage error'));

        // Act
        await presenter.startFast();

        // Assert
        expect(presenter.isFasting, isFalse);
      });
    });
  });
}
```

### Key Patterns

- **Mock StorageService** — never call SharedPreferences directly in tests
- **Test success and error paths** — both are required
- **Verify method calls** — use `verify()` to confirm persistence is called
- **Use `verifyNever()`** — ensure methods aren't called when they shouldn't be

## Service Layer Testing

```dart
@GenerateMocks([StorageService])
void main() {
  late NotificationService service;
  late MockStorageService mockStorage;

  setUp(() {
    mockStorage = MockStorageService();
    service = NotificationService(storage: mockStorage);
  });

  group('NotificationService', () {
    test('Given valid schedule, When scheduleNotification called, Then stores schedule', () async {
      when(mockStorage.saveNotificationSchedule(any)).thenAnswer((_) async {});

      await service.scheduleNotification(DateTime.now().add(Duration(hours: 16)));

      verify(mockStorage.saveNotificationSchedule(any)).called(1);
    });
  });
}
```

## Summary — Testing Each Layer

| Layer | What to Test | What to Mock |
| --- | --- | --- |
| **Model** | `fromJson`/`toJson`, field validation | Nothing |
| **Presenter** | State transitions, RPG math, XP | StorageService |
| **Service** | Scheduling, persistence logic | StorageService |
| **Widget** | UI renders, button taps, state display | Presenter |

## Common Verification Patterns

```dart
// Verify method was called once
verify(mock.method()).called(1);

// Verify method was called with specific arguments
verify(mock.method(argThat(equals('expected')))).called(1);

// Verify method was never called
verifyNever(mock.method());

// Verify call order
verifyInOrder([
  mock.method1(),
  mock.method2(),
]);
```
