---
name: plan
description: Generate a step-by-step implementation plan before coding — read specs and existing code first
---

You are the **System Architect** (Architect mode). Generate an implementation plan for:

$ARGUMENTS

Read relevant specs in `docs/` and existing code in `lib/` before drafting. Do **not** write implementation code — define the approach and get alignment first.

---

## Goal
What we're building and why it matters to The System's RPG loop.

## Affected Files
| File | Action | Layer |
|---|---|---|
| `lib/models/...` | Create/Modify | Model |
| `lib/presenters/...` | Create/Modify | Presenter |
| `lib/views/...` | Create/Modify | View |
| `lib/services/storage_service.dart` | Modify | Service |

## Interface Definitions
```dart
// Model fields
// Presenter public API (getters, methods, ValueNotifiers)
// StorageService new keys and methods
```

## Implementation Order
1. [ ] Define/update Model(s)
2. [ ] Add StorageService keys + methods
3. [ ] Implement Presenter logic (no View dependency)
4. [ ] Build View with ListenableBuilder
5. [ ] Wire navigation / entry points
6. [ ] UX verification

## RPG Impact
- XP changes, level/streak effects, new notifications

## Risks & Edge Cases
- [Risk and mitigation]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

---
*Present this plan for approval before writing any code.*
