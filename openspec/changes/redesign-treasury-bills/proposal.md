## Why

The Bills tab is the third Treasury screen in the Nudgr redesign. It already has a month selector, a
Pending/Paid/Installments stats bar, credit-card cards, and per-type sections (bills, receivables,
set-asides, installments) — but it opens with a flat list and never spotlights the one thing a bills
screen exists to prevent: **the next bill about to come due**. The reference
(`Nutrition Focus Treasury.dc.html`, Frame 3) leads with a warm **DUE SOON hero** — the most imminent
unpaid bill with its amount, a due countdown, and a one-tap **Mark paid**. This is a **restyle +
finally-surface**: add that hero on top of the existing screen; everything already there stays.

## What Changes

- **Add a DUE SOON hero** at the top of the Bills list: a bills-accent (orange) gradient card
  spotlighting the soonest-due unpaid bill — a "DUE IN N DAYS" / "Overdue by N days" label, the bill
  name, a "{category} · due {date}" subtitle, the amount, a full-width **Mark paid** button (routes to
  the existing mark-paid sheet), and an edit affordance (existing edit sheet). Shown only when a bill
  is due within a week or overdue; hidden otherwise.
- **Add additive presenter getters** for it: `imminentUnpaidBill`, `billDueDate`, `billDaysUntilDue`,
  and `billDueInfo` (label + overdue + imminent) — pure derivations over existing bill state.
- **Escalate to the danger accent when overdue** (icon + accent), else the bills-orange accent.
- Everything else on the tab is unchanged (month selector, stats bar, credit cards, all sections,
  the FAB, and all sheets). Material icons + theme tokens only.

Non-breaking. No model/storage/navigation change; the hero reuses the existing mark-paid and edit
flows.

## Non-goals

- **No presenter/business-logic rewrite.** Mark-paid, receivables, set-asides, installments, and the
  credit-card statement logic are untouched; the new getters are pure and additive.
- **No reminder/notification plumbing.** The reference's bell button is not added; the hero surfaces
  Mark-paid + Edit only (no new notification path in this increment).
- **Not a rebuild of the sections or the stats bar** (they already match the reference's intent) and
  **not the "Coming up" unified bill+receivable timeline** — captured for a later increment.
- **No data migration, no new dependencies.**

## Capabilities

### New Capabilities
- `treasury-bills`: The Bills tab's due-soon hero — a spotlight for the most imminent unpaid bill
  (countdown/overdue label, name, category·due-date subtitle, amount, Mark-paid + Edit actions),
  shown only when due within a week or overdue, with an overdue danger state, on top of the existing
  bills screen; theme-aware (no hardcoded per-mode colors).

### Modified Capabilities
<!-- None. openspec/specs/ contains only `hub`; no existing bills capability, no other spec-level
     requirement changes. -->

## Impact

- **New:** `lib/views/treasury/bills/due_soon_hero.dart` (dumb hero widget).
- **Modified:** `lib/presenters/bills_receivables_presenter.dart` (additive `imminentUnpaidBill`,
  `billDueDate`, `billDaysUntilDue`, `billDueInfo`); `lib/views/treasury/bills/bills_receivables_view.dart`
  (a `_DueSoonHeroSection` at the top of the list).
- **Reuses (unchanged):** the mark-paid + edit sheets, `_StatsBar`, all sections, `finance_format.dart`,
  theme tokens.
- **Deps:** none new. **Risk:** low — additive hero over unchanged flows; hidden entirely when no bill
  is due soon, so no regression to the existing screen. Verified with a widget test on the hero.
