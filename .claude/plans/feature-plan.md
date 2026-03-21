# Feature Implementation Plan Template

> Copy this template when starting any non-trivial feature. Fill it out with the Architect agent (`/plan`), get alignment, then hand to the Builder agent (`/feature`).

---

## Conflict Check (complete before writing anything else)

Before finalising this plan, verify the following against all existing plans in `.claude/plans/`:

| Check | Question | Finding |
|---|---|---|
| **File overlap** | Does any existing plan Create or Modify the same files listed below? | |
| **Model overlap** | Does any plan define the same model class or add the same StorageService key? | |
| **Presenter split** | Is the logic being added already owned by another plan's new Presenter? | |
| **XP routing** | Does this plan call `StatsPresenter.addXp()` directly? (Flag if Plan 008 is not yet merged — calls will be refactored.) | |
| **HubScreen** | Does this plan unlock a Hub card? If so, use `moduleSubtitleGetters`/`moduleOnTapOverrides` pattern from Plan 001 — not new constructor params. | |
| **Supersedes** | Does this plan make an older plan redundant? Mark the older plan SUPERSEDED. | |
| **Dependency order** | List every plan that must ship before this one can be implemented. | |

> If any row has a finding, resolve it before implementation begins — either by adjusting this plan, updating the conflicting plan, or explicitly sequencing them.

---

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
