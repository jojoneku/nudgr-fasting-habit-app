# Plan 027 — Resolution Clarity + AI Tier Parity

> **Status:** Draft, in progress (Wave 1 implementing now, Wave 2 awaiting confirmation).
> **Goal:** Make the food-log resolution path visible, trustworthy, and recoverable. Then bring on-device AI up to feature parity with cloud so user experience degrades gracefully across tiers.

---

## 1. Why this exists

Two real pain points surfaced after Plan 026 shipped:

1. **Bad personal-dict entries are sticky.** Personal dict bypasses cloud entirely. If a wrong match was ever auto-promoted (especially in old v9 paths), every subsequent log of that name silently uses the wrong food. No UI to see or edit the dict.
2. **The resolution path is invisible.** Today, a cloud-resolved DB hit, a local FTS DB hit, and a dict hit all render the same `DB` badge. The `~` badge for AI estimates blends keyword-density (low quality) with cloud / on-device estimates (much higher quality).

The user also wants the on-device tier to feel like a real tier, not a degraded fallback — same single-call extract + resolve + estimate pattern, with a prompt to download Qwen if it's not present.

---

## 2. Wave 1 — Resolution clarity (lightweight, no model changes)

| Item | What | Effort |
|---|---|---|
| **A. Behavioral guardrail** | Only auto-promote to personal dict when the match came from cloud at confidence ≥ 0.8. Local FTS / scorer matches never auto-promote. This prevents future "rice → Sapin-Sapin" stickiness. | ~10 min |
| **B. Settings "Reset learned foods"** button | Nuclear-option clear of `_personalDict`. Confirmation dialog. | ~15 min |
| **C. Method-aware badges** | Replace generic `~` and `DB` with: `Cloud`, `Local AI`, `DB`, `You` (personal dict), `~` (keyword density fallback only). The `EstimationSource` enum gains `cloudAi` and `localAi` variants; badge colors map cleanly. | ~20 min |
| **D. Learned foods in Food Library** | New section / tab in `FoodLibraryScreen` listing personal dict entries with macros + last-used timestamp + tap-to-delete. | ~30 min |

Total Wave 1: ~1.5 hours.

### 2.1 Behavioral guardrail — exact rules

| Path | Auto-promote? | Why |
|---|---|---|
| Cloud `parseFoodWithCandidates` resolved food_id at conf ≥ 0.8 | ✅ yes | Cloud has the most context; high confidence is meaningful |
| Cloud open-ended estimate (no food_id) at conf ≥ 0.8 | ✅ yes | Same reason; means user gets free repeat lookups for off-DB foods |
| On-device extract + local hybrid resolve at conf ≥ 0.75 (current) | ❌ NO | Higher false-positive risk; the dict is a stronger signal than a single resolve |
| Personal-dict hit | n/a | Already in dict |
| Keyword-density fallback | n/a | Already gated; never promote |

The trade: users who never sign in to cloud will see slower long-term feel because the dict never grows automatically. We compensate with explicit "Save to my foods" affordances on each chat row (already partially supported via `learnFromEntry`).

### 2.2 Method-aware badges — palette

| Source | Badge | Color | Meaning |
|---|---|---|---|
| `EstimationSource.db` | `DB` | onSurfaceVariant | Local DB hit (no AI involvement) |
| `EstimationSource.cloudAi` (new) | `Cloud` | primary | Cloud picked from candidates OR estimated |
| `EstimationSource.localAi` (new) | `Local AI` | tertiary | On-device picked OR estimated |
| `EstimationSource.personalDict` | `You` | onSurfaceVariant | From your learned foods |
| `EstimationSource.keywordDensity` | `~` | error | Keyword bucket fallback — low confidence |
| `EstimationSource.userManual` | `Set` | onSurfaceVariant | User typed exact macros |
| `EstimationSource.aiPerItem` (legacy) | `AI~` | gold | Pre-cloud-tier estimate, kept for backward compat |

The presenter sets the right variant based on which branch resolved the entry. We migrate `aiPerItem` usage to `cloudAi` / `localAi` over time.

---

## 3. Wave 2 — On-device parity + first-run flow (bigger, awaiting confirmation)

### 3.1 On-device single-call parity

Today's on-device path:
```
extractFoodItems(text)  →  per-item local FTS resolve  →  keyword fallback
```

Cloud's pattern:
```
parseFoodWithCandidates(text, candidates) → returns items with food_id OR macros
```

**Proposal:** Add an on-device `parseFoodWithCandidates` impl that does the same job. Qwen 0.6B is small but with strict JSON output + few-shot examples it can:
- Extract items + grams (already does this)
- Pick from a candidate list by ID (simpler than free generation)
- Output sensible macros for unmatched items (it's been trained on nutrition data implicitly)

**Realistic expectations:** Qwen will be less accurate than Haiku — pick wrong candidates more often, hallucinate macros for unknowns. We compensate by:
- Lower confidence thresholds (don't auto-promote below 0.9 for on-device)
- Show "Local AI" badge so user knows results are best-effort
- Keep the on-device tier as a clear quality step below cloud

**Effort:** ~2 hours, plus iteration on the prompt + few-shot.

### 3.2 First-run AI prompt

Trigger when:
- User opens chat input for the first time AND no cloud + no on-device installed
- OR user logs while cloud is off AND no on-device installed

UX:
```
┌────────────────────────────────────────────┐
│  Set up smart food logging                 │
│                                            │
│  Sign in to use Cloud AI (~$0 to you,      │
│  best quality), or download an on-device   │
│  AI (~586 MB, works offline, slightly      │
│  less accurate).                           │
│                                            │
│  [ Sign in ]  [ Download AI ]  [ Skip ]    │
│                                            │
│  Without either, food logging will use     │
│  keyword matching only — low accuracy for  │
│  out-of-database foods.                    │
└────────────────────────────────────────────┘
```

"Skip" remembers the choice; doesn't nag again unless user goes 7 days then logs again.

**Effort:** ~1 hour.

---

## 4. Implementation order

| Step | Phase | Time |
|---|---|---|
| 1 | Wave 1.A — Behavioral guardrail | 10 min |
| 2 | Wave 1.C — Method-aware badges (enum + badge UI) | 20 min |
| 3 | Wave 1.B — Settings reset button | 15 min |
| 4 | Wave 1.D — Learned foods in Library | 30 min |
| 5 | Wait for user confirmation on Wave 2 |  |
| 6 | Wave 2.1 — On-device parity | 2 hr |
| 7 | Wave 2.2 — First-run prompt | 1 hr |

---

## 5. Non-goals

- A "verify dict entries against cloud" background job. Too much complexity for marginal benefit.
- Multi-turn clarification dialogs in food logging (Plan 026 rejected this).
- Replacing Qwen with a larger on-device model (separate roadmap).
