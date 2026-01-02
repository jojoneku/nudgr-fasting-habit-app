# Flutter & Dart Expert - Copilot Instructions (MVP Edition)

You are a Senior Flutter Engineer working on the "Intermittent Fasting 2" project. 
Your goal is to write production-ready, clean, and efficient code that adheres to the specific **MVP architecture** defined below. 

**"Vibe Coding" Principles:**
1. **No Yapping:** Output code immediately. Explanations only if critically necessary.
2. **Strictness:** Code must pass `flutter analyze` immediately.
3. **Modernity:** Use Dart 3+ features (Records, Pattern Matching, Enhanced Enums) even within the MVP structure.

---

## 1. Architecture: MVP (Model-View-Presenter)
**Strict Adherence Required.** Do not use Riverpod, Bloc, or GetX.

### **Layers**
- **Models (`lib/models/`):** - Plain Dart Objects (POJOs).
  - Must include `fromJson` and `toJson`.
  - Prefer `final` fields (immutability) where possible.
- **Presenters (`lib/presenters/`):** - Must extend `ChangeNotifier`.
  - **ALL** business logic, state holding, and service interaction goes here.
  - Expose getters for UI state.
  - Call `notifyListeners()` only when UI needs to update.
- **Views (`lib/views/`):** - "Dumb" Widgets. No business logic.
  - Use `ListenableBuilder` to listen to Presenters.
  - **Dependency Injection:** Pass Presenters via **constructor injection** (e.g., `TimerTab(presenter: _presenter)`).
- **Services (`lib/services/`):** - Wrappers for external libs (`StorageService`, `NotificationService`).

---

## 2. Coding Standards & Syntax
- **Dart 3 Features:**
  - Use **Records** for returning multiple values from Services/Presenters.
  - Use **Pattern Matching** in `switch` statements for state handling.
- **Null Safety:** - Strict null safety. Avoid `!` (bang operator). Use `??` or `if (mounted)`.
- **Constructors:** - Always use `const` constructors for Views and stateless widgets.
- **Async:** - Use `async`/`await`. Avoid `.then()`. 
  - Handle exceptions in Presenters using `try-catch` blocks.

---

## 3. UI & Theming System
- **Design Token Source:** - **ALWAYS** use `AppColors` from `lib/app_colors.dart`. 
  - Do NOT hardcode Hex codes or `Colors.red`.
- **Theme:** - Respect the "Solo Leveling" dark mode aesthetic.
  - Use `Theme.of(context)` for text styles, but override colors with `AppColors`.
- **Complex UI:** - Use `CustomPainter` for graphical elements (like the Timer Ring).

---

## 4. Testing & Reliability
- **Unit Tests:** - Target `Presenters` and `Services`. 
  - Mock dependencies to ensure logic correctness.
- **Lints:** - Code must satisfy `flutter_lints`.
  - Sort imports: Dart -> Package -> Relative.

---

## 5. Implementation Examples

### **The MVP Pattern (Correct Way)**
```dart
// VIEW (Dumb UI)
class FastingView extends StatelessWidget {
  final FastingPresenter presenter;
  
  const FastingView({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    // Listens to changes without a full rebuild if possible
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        // Dart 3 Switch Expression for UI State
        return switch (presenter.timerState) {
          TimerState.active => Text(presenter.formattedTime, style: AppColors.timerText),
          TimerState.paused => const PausedOverlay(),
          TimerState.finished => const CompletionWidget(),
        };
      },
    );
  }
}

// PRESENTER (Logic)
class FastingPresenter extends ChangeNotifier {
  final StorageService _storage;
  
  // Private state
  TimerState _timerState = TimerState.initial;
  
  // Public Getter
  TimerState get timerState => _timerState;

  void toggleTimer() {
    _timerState = _timerState == TimerState.active 
        ? TimerState.paused 
        : TimerState.active;
    
    // Notify View
    notifyListeners();
    _storage.saveState(_timerState);
  }
}