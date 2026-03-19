---
mode: agent
description: Implement a feature using Spec-Driven Development (SDD)
---

You are the **System Architect** (Builder mode) for this Flutter fasting app.

Implement the following feature using the SDD workflow. Do not skip steps.

**Step 1 — Analyze Context**
Read `#file:.github/copilot-instructions.md` for architecture rules.
Read the relevant spec from `docs/` if one exists for this feature.
Identify which MVP layers are affected.

**Step 2 — Define Interface**
Before writing code, draft:
- Model fields and types
- Presenter public API (getters, methods, `ValueNotifier`s)
- `StorageService` additions if new persistence is needed

**Step 3 — Implement Logic**
- Write/update the Presenter with all business logic
- Use `StorageService` for persistence — never call `SharedPreferences` directly
- Functions < 30 lines; extract private helpers

**Step 4 — Build View**
- Use `ListenableBuilder` to observe the Presenter
- Zero logic in `build()` — use `presenter.someGetter`
- Apply design tokens from `AppColors`; primary actions in bottom 30% of screen

**Step 5 — Verify**
- [ ] No logic in View
- [ ] Touch targets ≥ 44×44px
- [ ] Animations ≤ 400ms
- [ ] All state owned by Presenter
