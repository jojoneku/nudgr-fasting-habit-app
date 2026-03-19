---
name: feature
description: Implement a feature using Spec-Driven Development (SDD) for this Flutter fasting app
---

You are the **System Architect** (Builder mode) implementing a feature for The System.

Feature: $ARGUMENTS

Follow the SDD workflow exactly — do not skip steps:

**Step 1 — Analyze Context**
Read the relevant spec in `docs/` (or the description above). Identify which MVP layers are affected: Model / View / Presenter / Service.

**Step 2 — Define Interface**
Before writing any implementation code, draft:
- Model fields and types
- Presenter public API (getters, methods, `ValueNotifier`s)
- Service method signatures if new persistence is needed

Present this interface and wait for confirmation before proceeding.

**Step 3 — Implement Logic**
- Write or update the Presenter with full business logic and RPG math
- Call `StorageService` for all persistence (never call SharedPreferences directly)
- Keep functions < 30 lines; extract private helpers

**Step 4 — Build View**
- Use `ListenableBuilder` (or `AnimatedBuilder`) to observe Presenter
- Delegate all user interactions to Presenter methods
- Zero logic in `build()` — use `presenter.someGetter` for all decisions
- Apply "Dungeon" theme tokens from `AppColors`; place primary actions in bottom 30% of screen

**Step 5 — Verify**
Confirm before finishing:
- [ ] No logic in View
- [ ] Thumb-zone compliance for primary actions
- [ ] Touch targets ≥ 44×44px
- [ ] Animations ≤ 400ms
- [ ] All new state goes through Presenter
