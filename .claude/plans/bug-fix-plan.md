# Bug Fix Plan Template

> Use this template for any non-trivial bug fix. Diagnose first, fix second.

---

## Bug Description
[What is happening vs. what should happen]

## Reproduction Steps
1. [Step 1]
2. [Step 2]
3. [Observed result]

## Root Cause Analysis

### Hypothesis
[Initial theory about the cause]

### Files to Investigate
| File | Reason |
|---|---|
| `lib/presenters/foo_presenter.dart` | Likely owns the broken state |
| `lib/services/storage_service.dart` | Persistence issue? |

### Confirmed Root Cause
[After reading the code — what is actually broken]

## Fix Plan

| File | Change | Layer |
|---|---|---|
| `lib/presenters/foo_presenter.dart` | [Describe change] | Presenter |

## Implementation Steps
1. [ ] Reproduce bug locally / confirm root cause
2. [ ] Apply minimal fix in the correct layer
3. [ ] Verify fix doesn't break adjacent behavior
4. [ ] Run `flutter analyze` — zero warnings
5. [ ] Manual test on device/emulator

## Regression Risk
- [What else could this change affect?]
- [How to verify no regression]

## Architecture Note
> If the bug required logic in the View to fix, that's a smell — refactor to Presenter.
