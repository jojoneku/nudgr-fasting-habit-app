# Design reference — Nudgr Focus

Static HTML exports of the **Nudgr Focus** design prototype. These are the
visual source of truth the app's redesign is built against (dark-mode phone
frames, `Plus Jakarta Sans`, Phosphor icons).

Each `*.dc.html` file is a self-contained set of phone-frame mockups for one
area. `support.js` is the design-doc runtime the frames load; open any
`.dc.html` in a browser to view it.

Committed here (rather than kept on a local machine) so cloud / remote work can
reference the designs directly.

## Key files

| File | Covers |
|---|---|
| `Nutrition Focus Treasury.dc.html` | Treasury: dashboard, ledger, bills, budget, history, cart, goals, account/txn sheets |
| `Nutrition Redesign.dc.html` | Nutrition tab redesign |
| `Nudgr All Screens.dc.html` | Every screen in one document |
| `Nudgr Design Tokens.dc.html` | Colors / type / spacing tokens |
| `Nudgr Directions.dc.html` | Overall design direction |
| `Nutrition Focus *.dc.html` | Per-area frames (Hub, Fasting, Weight, Stats, Quests, Coach, Settings, Onboarding, …) |

## Not included

To keep the (public) repo small, these were intentionally left out:

- `Nudgr Prototype - Standalone.html` (~6.9 MB single-file interactive prototype)
- `screenshots/`, `uploads/`, `.thumbnail`

They remain on the original machine if the full interactive prototype is needed.
