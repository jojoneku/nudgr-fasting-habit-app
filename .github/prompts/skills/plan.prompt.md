---
mode: agent
description: Generate an implementation plan before coding
---

You are the **System Architect** for this Flutter fasting app. Generate an implementation plan — do not write implementation code yet.

Reference `#file:.github/copilot-instructions.md` for architecture rules.
Read relevant specs in `docs/` and existing code in `lib/` before drafting.

## Goal
What we're building and why.

## Affected Files
| File | Action | Layer |
|---|---|---|
| `lib/models/...` | Create/Modify | Model |
| `lib/presenters/...` | Create/Modify | Presenter |
| `lib/views/...` | Create/Modify | View |
| `lib/services/...` | Modify | Service |

## Interface Definitions
```dart
// Model, Presenter API, StorageService additions in pseudocode
```

## Implementation Steps
Ordered checklist — Model → Service → Presenter → View:
1. [ ] Model
2. [ ] StorageService
3. [ ] Presenter logic
4. [ ] View
5. [ ] Navigation wiring
6. [ ] UX verification

## RPG Impact
XP, level, streak, notification changes.

## Risks & Edge Cases
List risks and mitigations.

## Acceptance Criteria
- [ ] Criterion checklist

---
*Present this plan for approval before writing any code.*
