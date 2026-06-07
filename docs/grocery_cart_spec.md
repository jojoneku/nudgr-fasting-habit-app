# Grocery Cart Running Total — Spec

> Plan: [.claude/plans/038-grocery-cart-running-total.md](../.claude/plans/038-grocery-cart-running-total.md)

## 🎯 Objective

Give a budget shopper a **live running total** while at the grocery. Items are added by name + quantity; the total updates instantly. Since no reliable free Philippine grocery price API exists (Open Food Facts does **not** recognize PH products), prices are **user-supplied** and **remembered** — entered once, then auto-filled on every future trip.

## 🧠 Conceptual Model

A **cart** is the current shopping session: a list of `CartItem`s. A **price memory** is a per-user store of `RememberedPrice` keyed by barcode (when known) or normalized name. Each cart item has one of three price states:

| State | Source | Total contribution | UI |
|---|---|---|---|
| `confirmed` | User typed / OCR'd this trip | exact | normal |
| `remembered` | Auto-filled from price memory | estimate | `~₱…`, "tap to confirm" |
| `unknown` | No price available | excluded | "No price · tap to add", counted as unpriced |

The total is always presented as a **breakdown** — `₱X confirmed · ~₱Y est · N unpriced` — so it never silently understates the spend.

## 📱 UI (Treasury → Cart tab)

- **Summary header** — big running total, breakdown line, optional budget row (remaining / over-budget).
- **Item list** — each row: name, price-state subtitle, −/+ quantity stepper, line total. Tap a row to set/confirm its price; swipe to remove.
- **Bottom bar** — primary "Add item" action (bottom 30%), clear-cart button.
- **Add-item sheet** — name (shows "Last paid ₱X" hint when remembered), quantity stepper, optional price. Blank price → remembered estimate or unpriced.

## 🔄 Flow

**Happy path:** Open Cart → Add "Eggs", qty 2, ₱8.50 → total shows ₱17.00 confirmed. Next trip, add "Eggs" with no price → auto-fills ~₱17.00 estimate.

**Missing price:** Add item, leave price blank, no memory → added as *unknown*; total unaffected, "1 unpriced" shown. Tap it later at the price checker → confirm → total updates and memory learns it.

**Stale price:** Remembered estimate looks wrong → tap → overwrite → becomes confirmed and memory self-corrects.

## 🛠 Technical Notes

- **Presenter:** `GroceryCartPresenter extends ChangeNotifier with SafeNotifier`. Constructor-injected `StorageService`. Totals via `fold`; auto-fill via `lookup()`; all RPG-free math lives here.
- **Persistence:** `StorageService` keys `grocery_cart`, `grocery_price_memory`, `grocery_budget` — user-scoped via `_k(userId)`. Local-only for now (cloud sync of price memory is a future enhancement).
- **Key normalization:** `RememberedPrice.keyFor()` → `barcode:<code>` or `name:<lowercased, space-collapsed>`.

## ⛔ Out of Scope (follow-up PRs)

- On-device OCR price capture (Phase 2) — `google_mlkit_text_recognition`, reads shelf tags. No external API.
- Optional barcode scan as a local memory key (Phase 2).
- Checkout → post total to Ledger as an outflow (Phase 3).
- Cloud sync of price memory.
