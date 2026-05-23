# Plan 028 — Food Matching & Estimation Hardening

## Problem statement

Three distinct failure modes remain after Plan 026/027:

| # | Symptom | Root cause |
|---|---------|-----------|
| A | "fried chicken" → logs "Korean fried chicken" / branded variant | FTS5 retrieves over-specific candidates; AI has no structural signal to reject them |
| B | User types "Pork Afritada"; log shows "Afritada (Pork/Chicken)" | Cloud path uses `hit.name` (DB canonical) not `item.name` (user's intent) |
| C | Edit flow feels dumb / produces wrong overwrite | Both edit methods call `FoodNlpParser` + legacy `_resolveOneDbItem` — Plan 026 cloud path is never reached on edit |

---

## Fix 1 — Candidate pre-scoring: push over-specific hits to the back  
**File:** `lib/presenters/nutrition_presenter.dart` → `_buildCandidatePool`

After FTS5 retrieval, re-sort each hit list by a **specificity-excess** heuristic before interleaving them into the round-robin pool.

```
queryWords  = normalised word-set of the user's query
extraWords  = candidateName.words ∖ queryWords
penaltyScore = extraWords.length / candidateName.words.length
```

Candidates with `penaltyScore > 0` are re-ranked behind zero-penalty candidates within their hit list. They stay in the pool (the AI can still pick them if they genuinely fit), but generic entries surface first.

**Why this helps:** BM25 doesn't penalise extra words — a 5-word candidate that fully contains the 2-word query can outrank a 2-word exact match. Pre-scoring corrects this before the Lambda even sees the pool.

**Important:** this is a re-rank, not a filter. Never hard-drop candidates; just reorder.

---

## Fix 2 — Display name preservation  
**File:** `lib/services/cloud_ai_coach_service.dart` → `_tryCloudParseFood`

When hydrating from a DB hit, use `item.name` (AI-normalised from the Lambda response — already the user's phrasing) instead of `hit.name` (DB canonical):

```dart
// Before
entry = hit.toFoodEntry(item.grams).copyWith(
  estimationSource: EstimationSource.cloudAi,
  confidence: item.resolverConfidence,
);

// After
entry = hit.toFoodEntry(item.grams).copyWith(
  name: _formatDisplayName(item.name),   // ← preserve user's phrasing
  estimationSource: EstimationSource.cloudAi,
  confidence: item.resolverConfidence,
);
```

**Why:** `item.name` comes from the Lambda's `"name"` field, which the AI sets to a short clean version of what the user typed ("Pork Afritada"). The DB hit's canonical name ("Afritada (Pork/Chicken)") is irrelevant to display — it's just the source of macros.

---

## Fix 3 — Route edits through the cloud path  
**File:** `lib/presenters/nutrition_presenter.dart` → `editChatFoodItem` + `editAllChatFoodItems`

Both methods currently call `FoodNlpParser.parse()` then `_resolveDbMatches()` — the pre-026 legacy pipeline. Replace with the same tiered strategy used by `_parseChatAsFood`:

```
editChatFoodItem(messageId, itemIndex, newText):
  1. Remove old entry from log (unchanged)
  2. Try _tryCloudParseFood(newText)   ← NEW — same as initial logging
     → if success: use result.entries, commit, return
  3. Fall back to FoodNlpParser + _resolveDbMatches  ← existing fallback
  4. Fall back to placeholder (unchanged)
```

Same for `editAllChatFoodItems` — call `_tryCloudParseFood` per item, fall through to legacy only on null.

**Why:** The edit path was never updated when Plan 026 promoted cloud-first logging. Every edit currently runs the old on-device resolver that: (a) ignores the personal dict, (b) skips the alias-aware FTS5, (c) has no macro estimation for unknown foods. This is the biggest quality gap.

**Caution:** `_tryCloudParseFood` can return multiple entries for a multi-item text (e.g. editing "rice and chicken"). The edit path already handles this in `editChatFoodItem` (it does `replaceRange`). No structural change needed there.

---

## Fix 4 — Raise cloud pick minimum confidence  
**File:** `lib/presenters/nutrition_presenter.dart` → `_tryCloudParseFood` (line ~1671)

```dart
// Before
} else if (item.resolvedFoodId != null && item.resolverConfidence >= 0.6) {

// After
} else if (item.resolvedFoodId != null && item.resolverConfidence >= 0.70) {
```

**Why:** 0.6 was set conservatively to catch marginal DB hits. With the improved Lambda prompt (Plan 028 prompt rules 1–2 already raising the bar for what gets a food_id at all), a 0.60–0.69 pick is almost always a weak match. Raising the floor means more items fall through to `estimated_macros` — which is correct behaviour when no good candidate exists.

---

## Fix 5 — Slash-variant annotation in candidate block  
**File:** `lambda_function.py` → `_fmt_candidate`

DB entries like "Afritada (Pork/Chicken)" use a `(A/B)` convention for multi-variant dishes. The AI often can't infer that "Pork Afritada" is a valid match for this. Annotate the candidate's slash-variants as readable aliases:

```python
def _fmt_candidate(c):
    name = c.get("name", "?")
    # expand "(Pork/Chicken)" → "also known as: Pork Afritada, Chicken Afritada"
    slash_note = _expand_slash_variants(name)
    ...
    line = f"- id: ..., name: {name}{macro}"
    if slash_note:
        line += f"  [{slash_note}]"
    return line

def _expand_slash_variants(name):
    # Match pattern: "Word (A/B)" → aliases "Word A", "Word B"
    import re
    m = re.match(r'^(.+?)\s*\(([^)]+/[^)]+)\)$', name.strip())
    if not m:
        return ""
    base, variants = m.group(1).strip(), m.group(2).split('/')
    aliases = [f"{base} {v.strip()}" for v in variants if v.strip()]
    return "also matches: " + ", ".join(aliases)
```

**Why:** Without this, the AI sees "Afritada (Pork/Chicken)" and isn't sure if "Pork Afritada" fits. With `[also matches: Afritada Pork, Afritada Chicken]`, the match is unambiguous.

---

## Fix 6 — Lambda: stronger match wording  
**File:** `lambda_function.py` → `_parse_food_with_candidates` rules block

Current Rule 1 already covers the structural principle. One addition to Rule 1:

> "Extra words in the candidate that are not in the user's query (after removing stopwords like 'the', 'a', 'with') are a specificity signal — the more extra content words, the lower your confidence should be."

This turns the binary "reject/accept" into a graded signal: the AI can pick at 0.72 instead of 0.85 when there's one minor extra word, but won't blindly set 0.9 for a heavy mismatch.

---

## Implementation order

| Priority | Fix | Effort | Impact |
|----------|-----|--------|--------|
| 1 | Fix 3 — edit path cloud routing | M | High — eliminates the regression |
| 2 | Fix 2 — display name preservation | S | High — UX correctness |
| 3 | Fix 4 — raise confidence floor | XS | Medium — fewer borderline false picks |
| 4 | Fix 5 — slash-variant annotation | S | Medium — fixes Afritada-type entries |
| 5 | Fix 1 — candidate pre-scoring | M | Medium — generic entries surface first |
| 6 | Fix 6 — lambda prompt update | XS | Low — incremental improvement |

Fixes 2, 3, 4 can ship together in one PR (all small, no new architecture).  
Fix 3 (edit routing) is a separate PR — slightly larger surface, worth isolated review.  
Fix 1 (pre-scoring) is a separate PR — new scoring logic warrants its own tests.

---

## What this does NOT change

- The FTS5 schema and alias expansion (Plan 026) — those stay
- The personal dictionary auto-learn thresholds — those stay (the fix is fewer wrong picks, not fewer learns)
- The on-device fallback path — untouched; Fix 3 adds cloud-first before it, not instead of it
