# Community Shared Grocery Prices — Spec (DRAFT, not approved)

> **Status:** Design proposal for review. **Do not implement** until the security/privacy model below is signed off.
> Builds on [grocery_cart_spec.md](grocery_cart_spec.md) and Plan 038. Per-user cloud sync of price memory ships separately (folded into the `userCollections` blob) and is a prerequisite.

## 🎯 Objective

Let users *optionally* contribute the prices they confirm to a shared pool, so a shopper sees a community estimate for items they've never personally bought — improving the cold-start that personal price memory can't cover on day one.

This is **not** a replacement for personal price memory. Personal memory (the user's own store-accurate prices) always wins; community data is a fallback estimate only.

## ⚖️ Why this is risky (and the constraints that follow)

| Risk | Constraint it forces |
|---|---|
| **Data quality** — prices vary by store, branch, region, promo, date | Every contribution must carry `store` + `region` + `observed_at`; clients see a **range / median**, never a single authoritative number |
| **Abuse / poisoning** — a public writable table invites garbage (₱1, ₱99999), spam, offensive names | No raw client writes. Contributions go through a **server-side edge function** that validates, rate-limits, and rejects outliers. Item names normalized + profanity-filtered |
| **Privacy** — shopping data is personal | Contribution is strictly **opt-in** (off by default). Contributions are **anonymized** — no `user_id`, no device id stored on the public row. A user can opt out and stop contributing at any time |
| **Trust** — clients must not be able to read raw, unaggregated contributions of others | Clients read only an **aggregates** view (median, count, range, last-updated) — never individual rows |
| **Moderation** — bad data slips through | A `report` path flags an aggregate; flagged items are suppressed pending review. Outlier rejection (e.g. drop values outside 1.5×IQR) runs server-side on each write |

## 🧱 Data model (Supabase)

Two tables + one view (all new; **manual migration**, per the deploy workflow):

- `community_price_contributions` — write-only via edge function. Columns: `id`, `item_key` (normalized name / barcode), `display_name`, `price`, `store`, `region`, `observed_at`, `created_at`. **No user identity.** RLS: no direct client `INSERT`/`SELECT`.
- `community_price_aggregates` — server-maintained rollup per `(item_key, region)`: `median_price`, `sample_count`, `p25`, `p75`, `min`, `max`, `updated_at`, `suppressed` (bool). RLS: client `SELECT` allowed (read-only), no write.
- Edge function `submit-community-price` — validates payload, profanity-checks name, rate-limits per device token, inserts a contribution, recomputes the aggregate with outlier rejection.

## 🔄 Flow

1. **Contribute (opt-in):** when a user confirms a price and has community sharing on, the app calls the edge function with `{item_key, display_name, price, store?, region}`. Fire-and-forget, anonymized.
2. **Consume:** for an item with no personal memory, the app queries `community_price_aggregates` by `(item_key, region)`. If a healthy sample exists (`sample_count ≥ N`, not `suppressed`), it offers the **median** as a `remembered`-style estimate, labeled "community ~₱X (n=…)".
3. **Report:** a long-press on a community estimate flags it; repeated flags suppress the aggregate.

Personal memory > community estimate > unknown. Community values never overwrite a confirmed personal price.

## 📱 UX

- **Settings toggle:** "Contribute my prices to the community (anonymous)" — default **off**, with a one-line privacy explainer.
- Community estimates are visually distinct from personal estimates (e.g. a small "community" chip) so the user knows the source and confidence (sample size).

## ⛔ Out of scope / open questions

- Region granularity (city vs. province?) and how to obtain it without precise location.
- Whether to instead contribute to **Open Prices** (Open Food Facts) rather than self-host — pro: shared ecosystem; con: poor PH coverage today, less control.
- Anti-abuse hardening (device attestation, captcha-equivalent) if spam becomes real.
- Cost/scale of edge-function invocations and aggregate recomputation.

## 📋 Recommendation

Ship **personal cloud sync first** (already in progress). Treat this community layer as a separate, explicitly-approved project — the value is mostly cold-start, which a **bundled seed price list** could also provide with none of the abuse/privacy/moderation surface. Decide bundled-seed vs. community before building either.
