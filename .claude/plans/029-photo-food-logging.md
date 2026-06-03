# Plan 029 — Photo Food Logging

> **Status:** Draft v2 (post-audit). Awaiting approval.
> **Scope:** Add photo-based meal logging with an optional text caption.
> Photo + (optional) text → same `ExtractedFoodItem[]` shape as text-only
> logging → flows into the existing commit pipeline unchanged.
> **Cost posture:** Reuses existing Bedrock Lambda; adds one new op.
> Haiku 4.5 vision = ~$0.001–0.002 per photo.
> **⛔ Hard blocker:** This feature must NOT ship until [Plan 034](034-audit-ai-backend-infra.md)
> SEV-1 (endpoint JWT verification + per-user daily cap) lands. See §0.

---

## 0. Post-audit revisions (READ FIRST)

A full-repo architectural review (Plans 030–035) surfaced four issues that this
draft, written before the audit, did not account for. The original sections below
are kept for context; **where they conflict with this section, this section wins.**

### 0.1 🔴 BLOCKER — gate behind endpoint auth + server-side cap ([Plan 034](034-audit-ai-backend-infra.md) SEV-1)
The original §3/§9 claim a "10/day cap enforced client-side + server-side." **There is
currently no server-side auth or rate limiting** — the Lambda calls Bedrock with zero
JWT verification. A vision op costs ~3× a text op, so adding `parseFoodFromImage` to an
open endpoint *increases* the existing billing-abuse exposure.
- **Photo logging is blocked until [Plan 034](034-audit-ai-backend-infra.md) SEV-1 is deployed** (Supabase JWT verify in-Lambda + per-user daily counter).
- The "10/day" cap moves to the **server** (authoritative, keyed on the JWT `sub`). The client cap stays only as a UX courtesy (show the cap message early), never as the enforcement boundary.
- Implementation order §12 is amended: **step 0 = land 034 SEV-1**, before any photo work.

### 0.2 🔴 Disable auto-learn for photo-sourced items ([Plan 033](033-audit-food-logging-ai-flow.md) H2)
The commit path auto-promotes any item with confidence ≥ 0.8 into the personal
dictionary permanently. Photo estimates (the example response returns 0.85 / 0.9) are
the *least*-verified input mode, so they would silently poison the dictionary and bypass
the DB forever after.
- `parsePhoto` must tag items with a `source: photo` (or `autoLearn: false`) flag and the commit path must **skip personal-dict promotion for photo items.** Only an item the user explicitly edits/confirms may learn.
- Add a test asserting a photo-logged item does NOT create a personal-dict entry.

### 0.3 🟠 Make per-item portion/macro editing prominent — do not rely on swap chips
Original open question §11 #5 ("photo items <0.6 → swap-chip UX") is moot: photo items
always have `food_id: null`, so there is no candidate set and `alternatives` is `const []`
— **swap chips cannot render.** The real failure mode is a *high-confidence wrong* vision
estimate (e.g. 0.85) committing silently with no correction affordance.
- Photo food rows must surface an obvious **edit-portion (grams) + edit-macros** affordance directly on the row (grams editing is the entire point per §1).
- Treat the vision `confidence` on its **own scale** — do NOT reuse the text pipeline's 0.6 / 0.7 / 0.8 gates (tuned for FTS-derived scores). Define photo-specific bands; default photo items to a "review portion" nudge regardless of model confidence.

### 0.4 🟠 Technical integration fixes (Plans 031 / 032)
- **Thumbnails as files, not inline base64.** Original §6 stores `photoThumbnailBase64` on `ChatMessage`. Chat messages persist into a SharedPreferences blob re-serialized on every write ([Plan 032](032-audit-performance-persistence.md) C1); 200 inline thumbnails ≈ 2MB re-encoded per chat save. **Store the thumbnail as a JPEG file in the app documents dir and reference it by relative path** (`photoThumbnailPath`) on `ChatMessage`. Delete the file when the chat row is deleted.
- **`parsePhoto` must be disposal-safe** ([Plan 031](031-audit-stability-lifecycle.md) C1). The 2–6s vision call ends in `notifyListeners()`; dismissing the sheet mid-call crashes a disposed notifier. Build `parsePhoto` on the `SafeNotifier`/`_disposed` guard from Plan 031.
- **Use a native compressor, off the UI thread.** Prefer `flutter_image_compress` (native) over pure-Dart `package:image`, which can block the UI thread ~1–3s decoding a 12MP photo. If `package:image` is kept, run it via `compute()` in an isolate. (Amends §6 and the §12 image-compressor step.)

### 0.5 🟡 Sequencing with the flow unification ([Plan 033](033-audit-food-logging-ai-flow.md) Phase 0)
This plan correctly hooks the **chat** flow (the good pipeline). [Plan 033](033-audit-food-logging-ai-flow.md) Phase 0
unifies the two logging entry points; do that **before or alongside** photo, not after —
they converge with zero conflict.

---

## 1. Why this exists

Three things photo logging unlocks that no amount of text-matcher tuning can:

| Pain | Photo fixes it because |
|---|---|
| User has no idea of grams ("a plate of adobo") | AI estimates portion from visual cues (plate area, garnish, utensils) |
| Multi-ingredient meals are tedious to type | One photo = full plate parsed in one shot |
| Filipino dishes whose names users don't know | Vision recognizes the dish even when the user can't name it |
| Restaurant food with no chain branding | Vision describes what it sees; estimation handles the rest |

The competitive read (see [Journable](https://www.journable.com/), [Cal AI], [Lose It Snap]): **photo is the single highest-UX-impact input mode in the category**. Every major calorie tracker that "feels magical" has it.

---

## 2. UX flow

```
┌───────────────────────────────────────────────────────────────────┐
│  Chat input bar                                                   │
│  ┌──────────────────────────────────────────┐  📷  bookmark  ↑  │
│  │ What did you eat or exercise?            │                    │
│  └──────────────────────────────────────────┘                    │
└───────────────────────────────────────────────────────────────────┘
                            ↓ tap 📷
┌───────────────────────────────────────────────────────────────────┐
│  PhotoCaptureSheet (bottom sheet)                                 │
│                                                                   │
│  [ Take photo ]   [ Choose from gallery ]                         │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
                            ↓ user picks/takes
┌───────────────────────────────────────────────────────────────────┐
│  PhotoPreviewSheet                                                │
│                                                                   │
│  ┌───────────────────────────────┐                                │
│  │                               │                                │
│  │     [ photo thumbnail ]       │                                │
│  │                               │                                │
│  └───────────────────────────────┘                                │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │ Add a note (optional) — e.g. "no rice in mine"           │    │
│  └───────────────────────────────────────────────────────────┘    │
│                                                                   │
│  [ Cancel ]                                          [ Log ]      │
└───────────────────────────────────────────────────────────────────┘
                            ↓ tap Log
                  [ spinner — 2–4 seconds ]
                            ↓
                  Items appear in chat feed
              (same row format as text logging,
               with a small 📷 indicator on the message)
```

**Editability:** parsed items use the existing chat-row UI, so the user can edit any item via the existing edit affordance just like a text-logged row.

---

## 3. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Input mode** | Photo + optional text caption | Strictly better than photo-only — caption resolves ambiguity for zero extra cost. Empty caption = pure photo mode. |
| **Vision model** | Bedrock Claude Haiku 4.5 (vision) | ~4× cheaper than Sonnet, sufficient for food identification. Sonnet is the upgrade path if quality is insufficient. |
| **Lambda op** | New op: `parseFoodFromImage` | Different prompt, different cost profile, different rate-limit policy. Sibling to `parseFoodWithCandidates`, not an extension. |
| **Candidate pool** | None — pure vision estimation | The pool is built from text FTS; useless for an image. Vision LLM identifies + estimates in one pass. |
| **Image transport** | Base64 in request body, client-resized to 1024px max | Simplest; no S3/multipart infra. Most food photos compress to <500KB JPEG at 1024px. Bedrock downsamples anyway. |
| **Image storage** | Not stored long-term; thumbnail (~10KB) saved as a **file in app docs dir**, referenced by path on the chat row (NOT inline base64 — see §0.4) | Privacy + storage cost + avoids re-serializing thumbnails into the chat blob. |
| **Free-tier gate** | 10 photos/day/user, enforced **server-side** (keyed on JWT `sub`); client cap is UX-only (see §0.1) | Prevents abuse; client-side enforcement is bypassable, so it cannot be the boundary. |
| **Permissions** | Reuse existing CAMERA permission + add READ_MEDIA_IMAGES for gallery | image_picker handles iOS automatically when we eventually need it. |

---

## 4. Architecture

```
┌─────────────────────────── CLIENT ────────────────────────────┐
│                                                               │
│  PhotoCaptureSheet                                            │
│      ↓                                                        │
│  image_picker (camera | gallery)                              │
│      ↓                                                        │
│  Resize to 1024px max (longest side), JPEG q=80               │
│      ↓                                                        │
│  Base64 encode + present caption field                        │
│      ↓                                                        │
│  CloudAiCoachService.parseFoodFromImage(b64, caption)         │
│      ↓ HTTPS                                                  │
└───────────────────────────┬───────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────── LAMBDA ────────────────────────────┐
│                                                               │
│  op = "parseFoodFromImage"                                    │
│  body = { image: <base64>, mimeType, caption? }               │
│                                                               │
│  Bedrock InvokeModel (anthropic.claude-haiku-4-5)             │
│      with content = [{type:image,...}, {type:text,...}]       │
│                                                               │
│  Response: same shape as parseFoodWithCandidates              │
│      { items: [{ name, grams, estimated_macros, ... }],       │
│        intent: "meal" | "single_dish" }                       │
│                                                               │
└───────────────────────────┬───────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────── CLIENT ────────────────────────────┐
│                                                               │
│  NutritionPresenter.logPhotoMeal(items, thumbnail)            │
│    → personal-dict lookup per item                            │
│    → commit via existing _commitFoodChat                      │
│    → ChatMessage rendered with 📷 indicator + thumbnail        │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**Key invariant:** the Lambda returns the same JSON shape as `parseFoodWithCandidates`, so everything downstream (commit pipeline, edit flow, telemetry, dislike button) works without modification.

---

## 5. Lambda contract

### Request

```json
POST /chat
{
  "op": "parseFoodFromImage",
  "body": {
    "image_base64": "<jpeg base64>",
    "mime_type": "image/jpeg",
    "caption": "no rice in mine"
  }
}
```

### Response (success)

```json
{
  "items": [
    {
      "name": "Chicken adobo",
      "grams": 180,
      "hyde": "Chicken adobo, Filipino braised chicken in soy sauce and vinegar",
      "food_id": null,
      "confidence": 0.85,
      "estimated_macros": {
        "calories": 320,
        "protein_g": 28.0,
        "carbs_g": 4.0,
        "fat_g": 21.0
      }
    },
    {
      "name": "Sliced cucumber",
      "grams": 50,
      "hyde": "Cucumber, raw, with peel, sliced",
      "food_id": null,
      "confidence": 0.9,
      "estimated_macros": {
        "calories": 8, "protein_g": 0.3, "carbs_g": 1.8, "fat_g": 0.1
      }
    }
  ],
  "intent": "meal"
}
```

### Response (no food detected)

```json
{ "items": [], "intent": "no_food", "reason": "no food detected in image" }
```

### Prompt rules (Lambda-side)

1. **Always set `estimated_macros`.** Photo mode never returns null macros — there's no DB candidate to fall back to.
2. **`food_id` is always null** for this op. (We could add candidate lookup later, but V1 skips it.)
3. **Decompose composite plates** into ingredients ("adobo + rice + cucumber" → 3 items), same rules as the text prompt.
4. **Honor the caption.** "No rice" overrides whatever the vision sees. "About half the plate is rice" adjusts portion.
5. **Return `intent: "no_food"` with empty items** when the image is clearly not food (pet, person, document, blurry).
6. **Same canonical-name and PH chain piece-size rules** as the text prompt for consistency.

---

## 6. Flutter changes

### New files

| File | Responsibility |
|---|---|
| `lib/views/nutrition/food_photo_sheet.dart` | Two-step bottom sheet: capture/pick → preview+caption → submit. ~250 LOC. |
| `lib/services/image_compressor.dart` | bytes → resized JPEG bytes at 1024px max, q=80. Uses native `flutter_image_compress` (off the UI thread); `package:image` only as an isolate-run fallback (see §0.4). ~40 LOC. |

### Modified files

| File | Change |
|---|---|
| `pubspec.yaml` | Add `image_picker: ^1.x`, `flutter_image_compress: ^2.x` (native; see §0.4). |
| `android/app/src/main/AndroidManifest.xml` | Add `READ_MEDIA_IMAGES` (CAMERA is already there from old barcode work). |
| `lib/services/ai_coach_service.dart` | Add abstract `parseFoodFromImage(bytes, mime, caption)` method. |
| `lib/services/cloud_ai_coach_service.dart` | Implement `parseFoodFromImage` — base64 encode, call lambda, parse response into `ParseFoodResult`. |
| `lib/services/on_device_ai_coach_service.dart` | Return `null` (no on-device vision in V1). |
| `lib/services/null_ai_coach_service.dart` | Return `null`. |
| `lib/presenters/nutrition_presenter.dart` | New method `parsePhoto(Uint8List bytes, String? caption)`. Disposal-safe (built on the `SafeNotifier`/`_disposed` guard from [Plan 031](031-audit-stability-lifecycle.md), see §0.4). Calls `_aiCoachCloud.parseFoodFromImage`, tags items `source: photo` / `autoLearn: false` (see §0.2), then runs results through the same `_commitFoodChat` path used by text logging — but the commit path must **skip personal-dict promotion for photo items.** |
| `lib/models/chat_message.dart` | Optional `photoThumbnailPath` field on `ChatMessage` (relative path to a JPEG in app docs dir — NOT base64, see §0.4). Renders as a small icon + tappable thumbnail; file is deleted when the row is deleted. |
| `lib/views/nutrition/nutrition_screen.dart` | Add 📷 icon button in `_ChatInputBar`, wired to `showFoodPhotoSheet(context, presenter)`. Add thumbnail indicator in food message footer. |

### New test files

| File | Coverage |
|---|---|
| `test/services/cloud_ai_coach_image_test.dart` | `parseFoodFromImage` parses success + no-food + malformed responses. |
| `test/services/image_compressor_test.dart` | Resize logic — orientation preserved, max dimension respected, quality bounded. |
| `test/presenters/nutrition_presenter_photo_test.dart` | `parsePhoto` flows through commit pipeline; **photo items do NOT create a personal-dict entry** (§0.2); disposing the presenter mid-parse does not throw (§0.4); cap message shown when the server reports the cap reached. |

---

## 7. Cost model

| Item | Cost |
|---|---|
| Bedrock Haiku 4.5 vision, ~1024×768 image | ~1,500 input tokens × $0.0008/1k = **$0.0012/photo** |
| Caption + system prompt | ~500 input tokens × $0.0008/1k = $0.0004 |
| Response (~600 tokens) | ~600 output tokens × $0.004/1k = $0.0024 |
| **Total per photo (worst case)** | **~$0.004** |
| 5 photos/day × 30 days | **~$0.60/user/month** |
| 10 photos/day × 30 days (the daily cap) | **~$1.20/user/month** |

Sonnet would be ~4× more expensive (~$0.016/photo). Haiku is the right starting point; promote to Sonnet only if accuracy benchmarks fail.

---

## 8. Out of scope for V1

- **On-device vision.** Adds 200MB+ in model weights for marginal benefit.
- **Multi-photo batch** (4 photos of the same meal from different angles). Complexity, marginal accuracy gain.
- **Video / mid-meal logging.** Niche.
- **Photo history / browsing past meal photos.** Privacy tradeoffs aside, it's a separate feature.
- **Streaming responses.** Photo parse is one-shot — no streaming benefit.
- **Editing the image after capture** (crop, rotate). image_picker has these built in; users can re-take if needed.
- **Photo of a packaged product's nutrition label.** Different prompt entirely; deserves its own plan if we want it.
- **Photo + DB candidate hybrid.** Adds complexity (need a text caption to drive FTS) for unclear gain. V1 trusts vision estimation; we can layer DB lookup as V2 if accuracy benchmarks demand it.

---

## 9. Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Bedrock vision misidentifies common Filipino dishes | Medium | Caption field lets users correct in V1. If systematic, fine-tune prompt with PH-specific examples; consider Sonnet upgrade. |
| Photo upload eats user data (mobile data) | Low | Client-side resize to 1024px keeps payloads <500KB. Show data-warning toast on first use over cellular. |
| Cost runs away if a user logs 50 photos/day | Low | 10/day cap enforced client-side + server-side. Cap message explains why. |
| Privacy concern: food photos sent to AWS | Medium | Document in privacy policy; AWS doesn't train on Bedrock inference data by default. Don't store photos server-side. |
| User photographs something embarrassing/private | Low | Same as any camera permission. We never store; we only parse. |
| Vision returns garbage JSON | Low | Existing `_parseExtractResponse`-style guards apply. If parse fails, snackbar "couldn't analyze this photo — try again or describe it in text." |
| Thumbnail bloats storage | Low | 1024px → 90px square JPEG thumbnail = ~5–10KB. 200 logged photos = 2MB. Fine. |

---

## 10. Test plan

### Reference photos (ship with the test fixture)

10 photos with known ground truth (you take these once, commit to `test/fixtures/photos/`):
- Plain plate of white rice (single ingredient)
- Chicken adobo with rice and cucumber (3-item composite)
- Sinigang na baboy bowl (broth-heavy soup)
- Jollibee Chickenjoy + rice + gravy (PH chain composite)
- Tapsilog (3-ingredient classic)
- A bowl of cereal with milk (Western composite)
- A blurry/dark photo (graceful-degradation test)
- A photo of a cat (no-food test)
- A photo of a packaged Lucky Me Pancit Canton bowl (brand recognition test)
- An empty plate (no-food edge case)

### Acceptance criteria

- **Top 8 of 10** identify the primary food correctly.
- **Calorie estimate within ±25%** of ground-truth on the 6 "normal" photos.
- **No-food cases** return `intent: "no_food"` without crashing.
- **End-to-end time** P50 ≤ 3 seconds, P95 ≤ 6 seconds (from photo capture to results visible).
- **Daily cap enforcement** works — 11th photo of the day shows the cap message and doesn't call Lambda.

### Regression tests

- Existing text-logging tests still pass unchanged (proves the commit pipeline reuse worked).
- Personal dict lookup still fires for photo-parsed items.
- Dislike button + telemetry still capture photo-logged entries.

---

## 11. Open questions

| Q | My default | Your call |
|---|---|---|
| Daily cap: 10 photos/day too low? Too high? | 10/day, **enforced server-side** (§0.1) | ? |
| Show thumbnail in chat feed, or just a 📷 indicator? | Thumbnail (90px) as a **file**, tappable to expand (§0.4) | ? |
| Free tier or paywall from day one? | Free during pilot, paywall later if cost grows | ? |
| iOS support timeline — same release or later? | Later (no `ios/` config exists yet); Android-first V1 | ? |
| ~~Should photo-parse items go through swap-chip UX when confidence < 0.6?~~ | **Resolved (§0.3):** swap chips can't render (`food_id` is null → no candidates). Use a prominent edit-portion/macros affordance instead. | — |
| Long-press a photo'd meal to "re-analyze with different model"? | Defer to V2 | ? |

---

## 12. Implementation order

0. **⛔ PREREQUISITE — land [Plan 034](034-audit-ai-backend-infra.md) SEV-1** (endpoint JWT verification + per-user daily cap). Photo work does not start until this is deployed (§0.1). Build the photo daily cap into the same server-side counter.
1. **Lambda op** (you or me on the lambda side — needs Bedrock prompt + handler), behind the now-authenticated endpoint. Ship to staging.
2. **Flutter service layer:** `ai_coach_service.dart` abstract + cloud impl + null/on-device impls. Wire to staging endpoint.
3. **Image compressor** (native `flutter_image_compress`, off the UI thread — §0.4) **+ tests.**
4. **PhotoCaptureSheet UI** (single file, ~250 LOC).
5. **Presenter integration** (disposal-safe `parsePhoto`, `source: photo` tagging, auto-learn skip — §0.2/§0.4) + file-based thumbnail rendering on the chat row.
6. **Telemetry hooks** (server-side cap is already enforced per step 0).
7. **Reference fixture photos + acceptance tests** (incl. the no-auto-learn and dispose-mid-parse assertions).
8. **Bump `_dbFilename` if any DB schema change needed** (not anticipated — V1 doesn't change `food_db.sqlite`).
9. **PR to `dev`.**
10. **Acceptance test pass before release-version-bump.**

Estimated total: **3–5 focused days** of Flutter work, **plus the [Plan 034](034-audit-ai-backend-infra.md) SEV-1 backend hardening as a hard prerequisite** (does not overlap — it must land first). Flutter effort is dominated by Lambda prompt iteration + PhotoCaptureSheet polish.
