# Feature Implementation Plan Template

> Copy this template when starting any non-trivial feature. Fill it out with the Architect agent (`/plan`), get alignment, then hand to the Builder agent (`/feature`).

---

## Feature Name
[Name of the feature]

## Goal
What we're building and why it matters to The System's RPG loop.

## Spec Reference
Link to the relevant spec: `docs/[feature]_spec.md`

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/` | Create/Modify | Model |
| `lib/presenters/` | Create/Modify | Presenter |
| `lib/views/` | Create/Modify | View |
| `lib/services/storage_service.dart` | Modify | Service |

## Interface Definitions

```dart
// === Model ===
class NewModel {
  final Type field;
  const NewModel({required this.field});
}

// === StorageService additions ===
static const String newKey = 'new_key';
Future<void> saveNewData(NewModel data);
Future<NewModel?> loadNewData();

// === Presenter public API ===
Type get computedValue;
Future<void> doAction();
final ValueNotifier<Type> someNotifier;
```

## Implementation Order
1. [ ] Define/update Model(s) in `lib/models/`
2. [ ] Add storage keys + methods to `StorageService`
3. [ ] Implement Presenter logic (no View dependency yet)
4. [ ] Build View with `ListenableBuilder`, delegate all actions to Presenter
5. [ ] Wire navigation / entry points in `main.dart` or parent widget
6. [ ] UX verification checklist

## RPG Impact
- XP awarded: [amount, trigger]
- Level/streak affected: [yes/no, how]
- Notifications triggered: [which, when]

## Risks
- [Risk and mitigation]

## UX Verification
- [ ] Primary CTA in bottom 30% of screen
- [ ] All touch targets ≥ 44×44px
- [ ] Micro-animations 150–300ms
- [ ] No animation > 400ms
- [ ] Glanceable status visible in < 1 second

## Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]
