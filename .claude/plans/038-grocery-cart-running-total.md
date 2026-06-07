# Plan 038 — Grocery Cart Running Total

**Status:** Phase 1 implemented (manual entry + price memory + running total + budget)
**Module:** Treasury (finance)
**Depends on:** StorageService, LedgerPresenter (optional checkout integration — future).

> **Decisions (locked in):**
> - **No external product/price API.** Researched Open Food Facts, Open Prices, Numbeo, RapidAPI grocery APIs — none reliably cover PH products. User confirmed Open Food Facts does not recognize PH foods. All price/name data is user-supplied + remembered locally.
> - **OCR = on-device text recognition** (reads price/name off shelf tag or receipt), NOT the cloud food-vision pipeline. Free, offline, and *not* blocked on Plan 029/034. (Phase 2 — follow-up PR.)
> - **Entry point:** Treasury tab ("Cart").
> - **Checkout → Ledger:** optional, user-triggered (Phase 3 — follow-up PR).

---

## 🎯 Goal

A budget shopping companion: while at the grocery, add items (manual first; OCR later), set quantity, and watch a **live running total** so you never blow your budget. Because no reliable free Philippine grocery price API exists, **price data comes from you** — entered once at first contact, then **remembered and auto-filled on every future trip**.

### Price states (core concept)
| State | Meaning | Counts in total as |
|---|---|---|
| `confirmed` | You typed/OCR'd the price this trip | exact |
| `remembered` | Auto-filled from your price memory (last paid) | estimate (`~`) |
| `unknown` | No price available, flagged | excluded; surfaced as "N unpriced" |

> Total renders as a breakdown: **₱847 confirmed** · ~₱120 est · 2 unpriced — never a single misleading number.

---

## 📦 Affected Files (Phase 1)

| File | Action | Layer |
|---|---|---|
| `lib/models/grocery/cart_item.dart` | Create | Model |
| `lib/models/grocery/remembered_price.dart` | Create | Model |
| `lib/presenters/grocery_cart_presenter.dart` | Create | Presenter |
| `lib/services/storage_service.dart` | Modify (keys + abstract methods) | Service |
| `lib/services/local_storage_service.dart` | Modify (impl, user-scoped) | Service |
| `lib/views/treasury/grocery/grocery_cart_view.dart` | Create | View |
| `lib/views/treasury/grocery/add_cart_item_sheet.dart` | Create | View |
| `lib/views/treasury/treasury_module_view.dart` | Modify (Cart tab) | View |
| `lib/views/hub_screen.dart` | Modify (thread presenter) | View |
| `lib/views/home_screen.dart` | Modify (build + dispose presenter) | View |
| `test/presenters/grocery_cart_presenter_test.dart` | Create | Test |
| `docs/grocery_cart_spec.md` | Create | Docs |

---

## 🔢 Phasing (each its own PR)

### Phase 1 — MVP (this PR): manual entry + price memory + running total + budget
Fully offline, zero network. The complete usable feature.

### Phase 2 — On-device OCR price capture (follow-up)
`google_mlkit_text_recognition` + camera → read price off shelf tag → fill `unitPrice` as `confirmed`. Optional barcode as a **local memory key only** (no external product DB). No network, no Open Foods.

### Phase 3 — Ledger integration (follow-up)
`checkout(postToLedger: true)` → create a `TransactionRecord` outflow for `grandTotal` against a chosen account, then `clearCart()`.

---

## 🎮 RPG Impact
- MVP: none (utility feature). Optional future hook: under-budget trip → small Treasury XP/streak (deferred).

---

## ⚠️ Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Stale remembered price | Shown as `~`estimate; one-tap overwrite confirms + updates memory. |
| Name-key collisions | Key on barcode when available; normalize name (lowercase/collapse spaces); store `displayName`. |
| Missing price tag (common in PH) | `unknown` state — item added with qty, surfaced in "N unpriced"; never blocks total. |
| App killed mid-shop | Active cart persisted on every mutation; reloads on launch. |
| Quantity types (0.5 kg) | `quantity` is `double`; unit label deferred. |
| Sign-out wipes local data | Price memory **syncs** (folded into the `userCollections` blob) → flushed to cloud before `clearUserData` and restored on re-login. Active cart + budget stay local (transient). |

---

## ✅ Acceptance Criteria (Phase 1)

- [x] Add an item with name + quantity and optional price; total updates live.
- [x] No-price item flagged `unknown`, shown in unpriced count, not zeroed into total.
- [x] Re-adding a previously priced item auto-fills last price as a `remembered` estimate.
- [x] Editing/confirming a price updates the total and persists to price memory.
- [x] Total renders as confirmed · estimated · unpriced breakdown, with optional budget remaining + over-budget indicator.
- [x] Cart and price memory survive restart; user-scoped.
- [x] Works fully offline — no external product/price API anywhere.
- [x] Presenter holds all math; View has no calculations in `build()`; colors via `Theme.of(context)`.
- [x] Presenter unit tests pass.
