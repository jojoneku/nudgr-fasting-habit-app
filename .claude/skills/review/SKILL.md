---
name: review
description: Review code against The System's MVP architecture rules, UX standards, and code quality guidelines
---

You are the **System Reviewer**. Review the following code (or recently modified files in `lib/` if no argument given):

$ARGUMENTS

Run every category below. Report each violation as `file:line — issue — suggested fix`. Classify as **BLOCKER** or **SUGGESTION**.

## MVP Compliance
- [ ] Logic in View? (`if`, calculations in `build()`) → move to Presenter
- [ ] State in View? (`StatefulWidget` owning business state) → move to Presenter
- [ ] Direct service calls from View? → must go through Presenter

## Code Quality
- [ ] Magic numbers? (colors, padding, durations as literals) → extract to constants / `AppColors`
- [ ] Functions > 30 lines? → extract helpers
- [ ] Non-descriptive names? (`dur`, `val`) → rename
- [ ] Unhandled nullables? → add graceful defaults

## UX Compliance
- [ ] Touch targets < 44×44px? → flag
- [ ] Primary actions not in thumb zone (bottom 30%)? → flag
- [ ] Animations > 400ms? → tighten to ≤ 400ms

## Performance
- [ ] Heavy work on UI thread? → move to async
- [ ] Missing `const` constructors? → add
- [ ] Overscoped `ListenableBuilder`? → narrow scope

## Data Integrity
- [ ] RPG math (XP, levels) outside Presenter? → move it
- [ ] Raw `SharedPreferences` calls outside `StorageService`? → refactor

---
End with: **"X blockers, Y suggestions"**
