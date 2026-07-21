## Context

The Cart tab (`grocery_cart_view.dart`) already implements the reference (Frame 7) closely — it was
built for it (Plan 038). It shows a RUNNING TOTAL header (grand total, confirmed/estimated/unpriced
breakdown, budget bar), a list of items with price-state subtitles and −/+ steppers, and a
Finish-trip / Add-item bottom bar, plus checkout + trip history the reference only hints at.

The lone drift is the accent for estimated ("remembered") prices: the reference uses blue; the code
used `colorScheme.secondary`.

## Goals / Non-Goals

**Goals:**
- Align the estimated-price accent to the reference's blue.

**Non-Goals:**
- Any structural or behavioral change; anything in the presenter.

## Decisions

- **Estimated → `context.appColors.fast` (blue).** The reference paints not-yet-confirmed prices in
  the blue domain accent; the code's `colorScheme.secondary` isn't that blue. Swap it in the three
  places the estimate accent appears (breakdown chip, item subtitle, line total). Rationale: the
  domain-accent extension is the sanctioned token source and keeps dark/light correct. *Alternative:*
  `colorScheme.primary` — equivalent in most themes, but `appColors.fast` names the intent (the
  domain blue) explicitly.
- **Leave confirmed (neutral) and unpriced (danger) as-is** — they already match the reference.

## Risks / Trade-offs

- **[Accent parity across themes]** → `appColors.fast` is defined for dark + light, so the estimate
  blue holds in both; no per-mode hardcoding.

## Migration Plan

None — a color-token swap. Ships on `feat/redesign-treasury`; rollback restores `secondary`.

## Open Questions

- None. This closes the six-tab Treasury redesign; the reference's remaining frames (cart checkout,
  add/edit sheets, spending calendar, goals, account setup) are existing flows already styled with the
  system components.
