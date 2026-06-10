# Plan 049 — Accessibility Pass (Incremental)

> Status: PLANNED — NOT IMPLEMENTED

**Author:** System Architect
**Date:** 2026-06-10
**Spec:** None — incremental hygiene plan. Explicitly **NOT a big-bang refactor**: four phases, screen-by-screen PRs, each independently shippable.

---

## Verified audit numbers (re-measured on `dev`, 2026-06-10)

| Finding | Audit said | Measured |
|---|---|---|
| View files using `Semantics` | ~5 / 107 | **5 / 110** — all five in `lib/views/treasury/` (account card, transaction tile, installment tile, categories sheet, account setup). Hub, timer, nutrition, quests: zero |
| Bare `GestureDetector(` in views | ~50 | **56** |
| Hardcoded `fontSize:` in views | 307 | **314**. Worst: `nutrition/log_meal_sheet.dart` (55), `nutrition/nutrition_screen.dart` (38), `tabs/history_tab.dart` (20), `treasury/bills/bills_receivables_view.dart` (17), `activity/activity_screen.dart` (16) |
| AppSpacing adoption | ~20% | **40 / 110 files (~36%)** — improving organically; tracked here but lowest priority |

Net effect today: TalkBack users get unlabeled tap targets on every core screen, and system font scaling is defeated wherever `fontSize:` bypasses `textTheme`.

---

## Phase 1 — Semantics on interactive elements (highest-traffic screens first)

One PR per screen, in traffic order: **HubScreen → fasting timer (home/tabs) → nutrition (nutrition_screen + log_meal_sheet) → ledger (transactions + chat entry) → quests tab → stats view**.

Per screen:
- Every bare `GestureDetector`/`InkWell` carrying an action gets a `Semantics(button: true, label: …)` wrapper or is migrated to a labeled `IconButton`/`FilledButton` where that's the simpler fix (also fixes ripple + focus for free).
- Icon-only buttons get `tooltip:`.
- Stateful toggles expose state (`Semantics(selected:)` / `toggled:`), progress text that's purely decorative gets `excludeSemantics` to cut chatter.
- Labels delegate to existing presenter getters (e.g. timer announces `presenter.summaryLabel`) — no logic in `build()` (rule 1).

**Done check per PR:** TalkBack walk of the screen — every actionable element announces a name + role.

## Phase 2 — Migrate hardcoded `fontSize:` to theme tokens

`lib/utils/app_text_styles.dart` already defines the full M3 ramp (display→label, w400–w700, Plus Jakarta Sans) injected as `ThemeData.textTheme`, plus `AppTextStyles.numeric()` for tabular figures. Migration rule:

- `fontSize: 22/16/14` headings → `textTheme.titleLarge/.titleMedium/.titleSmall`; body/label sizes map likewise; one-off odd sizes snap to nearest token (`copyWith` only for weight/color, **never** size).
- Big timer/metric numerals → `AppTextStyles.numeric(fontSize:)` is acceptable *only* inside the dedicated countdown widgets where M3 sizes genuinely don't fit; everything else uses the ramp so `MediaQuery` text scaling applies.
- PR order = worst-first: `log_meal_sheet` (55) → `nutrition_screen` (38) → `history_tab` (20) → `bills_receivables_view` (17) → `activity_screen` (16) → long tail batched by folder (~6–8 PRs total).
- Opportunistic only: while editing a line for fontSize, swap adjacent magic-number padding to `AppSpacing` tokens — but no spacing-only churn PRs.

## Phase 3 — Semantic values for custom-painted charts

`CustomPaint` is invisible to screen readers. Targets: activity rings (`activity/`), nutrition macro pie/progress arcs, treasury pie/heatmap, stat radar in `stats_view`.

- Wrap each painter in `Semantics(label: …, value: …)` with presenter-supplied strings — e.g. rings announce "Steps: 7,200 of 10,000 — 72%", pie announces top-3 slices. Presenters grow small `*Semantics` getters; painters stay dumb.
- Decorative-only painters (glows, dividers) get `ExcludeSemantics`.
- One PR per chart family (rings / pies / radar+heatmap), ~3 PRs.

## Phase 4 — Text-scale smoke test + regression guard

1. **Smoke test:** widget tests pumping the top screens inside `MediaQuery(textScaler: TextScaler.linear(1.3))` asserting no `RenderFlex` overflow exceptions; plus a manual QA pass at device font "Largest".
2. **Lint guard (cheap first):** CI grep step — fail if `fontSize:` count in `lib/views/` *increases* vs a checked-in baseline file (`tool/a11y_baseline.txt`), and if a changed view file adds a bare `GestureDetector(` with `onTap` and no `Semantics`/`Tooltip` within the diff hunk. Ratchet the baseline down as Phase 2 PRs land.
3. Upgrade to a proper `custom_lint` rule only if the grep guard proves noisy — don't start there.

---

## Sequencing & risks

| Risk | Mitigation |
|---|---|
| Token migration subtly changes visual size/weight | Per-screen PRs with before/after screenshots in PR body; nearest-token rule, no invented sizes |
| Semantics wrappers break existing widget tests (extra nodes) | Run the screen's widget tests in the same PR; prefer `Semantics` over restructuring the tree |
| Grep guard false-positives block CI | Guard warns-only for its first two weeks, then enforces |
| Scope creep into a design-system rewrite | AppSpacing adoption stays opportunistic; anything bigger gets its own plan |

Phases 1 and 2 can interleave (different files); Phase 4's guard lands as soon as the first Phase 2 PR merges so the count only ratchets down.

## Acceptance Criteria

- [ ] Hub, timer, nutrition, and ledger screens fully navigable by TalkBack with meaningful announcements
- [ ] `fontSize:` count in `lib/views/` reduced from 314 to <50 (numeric countdown widgets exempt and documented)
- [ ] Activity rings, macro pie, and stat radar expose label + value semantics
- [ ] 1.3× text-scale smoke tests green; no overflow on top screens
- [ ] CI guard prevents `fontSize:`/unlabeled-GestureDetector regressions
- [ ] Every PR: one screen or chart family, `--base dev`, screenshots attached
