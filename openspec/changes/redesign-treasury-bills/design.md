## Context

The Bills tab (`bills_receivables_view.dart`, ~1.9k lines) is mature: a month selector, a
`_StatsBar` (Pending/Paid/Installments), credit-card cards, and sections for bills, receivables,
set-asides, and installments, each with its own tiles and mark-paid/edit/received sheets. The
`bills` getter is already ordered unpaid-first then by due day, so the most imminent unpaid bill is
`bills.where((b) => !b.isPaid).first`.

The reference (Frame 3) adds one thing the current screen lacks: a **DUE SOON hero** — a warm
gradient card at the top spotlighting that next bill with a due countdown and a one-tap Mark-paid.

## Goals / Non-Goals

**Goals:**
- Surface the most imminent unpaid bill in a hero, reusing the existing mark-paid/edit flows.
- Keep all presenter math additive and pure; keep the hero a dumb widget.

**Non-Goals:**
- Reminder/notification wiring (the reference's bell), a unified bill+receivable "Coming up"
  timeline, or any change to the sections, stats bar, or sheets.
- Any model/storage change or migration.

## Decisions

- **Additive presenter getters, no state.** `imminentUnpaidBill` (first unpaid from the already-sorted
  `bills`), `billDueDate` (month + clamped dueDay), `billDaysUntilDue` (vs today), and `billDueInfo`
  (label + overdue + imminent). Rationale: keeps date math out of `build` (Rule 1) and reusable.
  *Alternative:* compute in the view — rejected (math in build).
- **Dumb hero widget fed primitives.** `DueSoonHero` takes name/amount/dueLabel/subtitle/overdue +
  callbacks; the view's `_DueSoonHeroSection` resolves them from the presenter (category name, due
  date via `DateFormat`). Rationale: testable widget, no presenter coupling.
- **Show only when due within 7 days or overdue.** A far-off next bill isn't a spotlight; the section
  returns `SizedBox.shrink()` otherwise, leaving the existing screen untouched.
- **Overdue escalates to the danger accent**, else the bills-orange accent — derived by blending the
  accent into `colorScheme.surface` (same token approach as the dashboard NET WORTH hero), so it
  works in dark and light.
- **Reuse existing flows.** Mark-paid routes to `_showMarkBillPaidSheet`; edit to `_showAddBillSheet` —
  no new sheets, no new mutation paths.

## Risks / Trade-offs

- **[Duplicate spotlight vs the bills list]** → The same bill also appears in the Bills section below;
  acceptable — the hero is a call-to-action, the list is the record (mirrors the reference).
- **[Due-day overflow (day 31 in a 30-day month)]** → `billDueDate` clamps the day to the month
  length, so no phantom rollover.
- **[Month-relative correctness]** → `billDaysUntilDue` uses the bill's own month, so a past-month
  unpaid bill reads as overdue and a future-month one as far off.

## Migration Plan

None — additive view/presenter only. Ships on `feat/redesign-treasury`; rollback removes the hero
section (the getters are inert if unused).

## Open Questions

- Later: a unified "Coming up" timeline merging upcoming bills + incoming receivables (reference), and
  optional reminder wiring on the hero — both out of scope here.
