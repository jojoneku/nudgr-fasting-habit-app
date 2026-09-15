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
- **Price book** (header 🧾 icon) — the full list of learned prices, searchable with the same typeahead ranking. Tap a row to correct it, swipe to forget it, the cart icon adds it to the trip, and "Add price" records one straight off a receipt with no cart line. Reached from the shared `GroceryCartView`, so mobile and web get it together.
- **Add-item sheet** — name with a **price-memory typeahead**, unit chips, quantity stepper (−/+ by the unit's step), optional price, and a live line preview. Blank price → remembered estimate or unpriced. "Add & next" is the filled primary action (the loop a shopper stays in); "Add & close" is secondary.

## 🔄 Flow

**Happy path:** Open Cart → Add "Eggs", qty 2, ₱8.50 → total shows ₱17.00 confirmed. Next trip, add "Eggs" with no price → auto-fills ~₱17.00 estimate.

**Missing price:** Add item, leave price blank, no memory → added as *unknown*; total unaffected, "1 unpriced" shown. Tap it later at the price checker → confirm → total updates and memory learns it.

**Stale price:** Remembered estimate looks wrong → tap → overwrite → becomes confirmed and memory self-corrects.

**Recall while typing:** Type "bear" → every past variant stays listed with its last price ("Bear Brand 1L · ₱92.00 each", "Bear Brand powdered milk 240g · ₱128.00 each") until one is tapped or the name is typed out. Tapping fills the name + unit and leaves the price blank, so the item lands as an **estimate**; "Use it" on the hint row copies the remembered price into the box instead, confirming it.

## 🛠 Technical Notes

- **Presenter:** `GroceryCartPresenter extends ChangeNotifier with SafeNotifier`. Constructor-injected `StorageService`. Totals via `fold`; auto-fill via `lookup()`; all RPG-free math lives here.
- **Persistence:** `StorageService` keys `grocery_cart`, `grocery_price_memory`, `grocery_budget` — user-scoped via `_k(userId)`. The active cart and budget are local-only (transient); the **price memory syncs** to the cloud (folded into the `userCollections` blob), so it backs up and survives sign-out / restores on re-login.
- **Key normalization:** `RememberedPrice.keyFor()` → `barcode:<code>` or `name:<lowercased, space-collapsed>`.
- **Price book:** `savePriceBookEntry()` / `deletePriceBookEntry()` / `clearPriceBook()` edit the memory directly. `savePriceBookEntry` takes `replacingKey` so a rename doesn't orphan the old key, and preserves `timesSeen` — correcting a price is not a purchase.
- **Typeahead:** `searchPriceMemory()` in `lib/utils/grocery_price_search.dart` — pure, tiered ranking (exact › prefix › word-prefix › contains › all-tokens › fuzzy), frequency then recency as the tiebreak. Reuses `food_fuzzy.dart` for compound splits ("bearbrand" → "bear brand") and Damerau–Levenshtein typo tolerance. Exposed as `GroceryCartPresenter.suggestions(query)`; an empty query returns the most-bought items. `lookup()` stays the exact-key hit that drives auto-fill.

## ✅ Also shipped (units, checkout, trip history)

- **Quantity units** — each item has an `ItemUnit` (pc/pack/kg/g/L/mL); price is shown per unit ("each" or "/kg"), the stepper increments by the unit's natural step, and the remembered price restores the unit.
- **Checkout** — "Finish trip" saves a `SavedTrip` snapshot to history, optionally posts the total to the Ledger as an outflow (account/category picker), then clears the cart.
- **Trip history** — past trips are saved (synced via `userCollections`); a trip can be reviewed, repeated (re-adds its items, re-priced from current memory), or deleted.

## ⛔ Out of Scope (follow-up PRs)

- On-device OCR price capture — `google_mlkit_text_recognition`, reads shelf tags. No external API. (Own PR — native deps + device testing.)
- Optional barcode scan as a local memory key.
- Community shared price database — see [grocery_community_prices_spec.md](grocery_community_prices_spec.md) (draft, not approved).
