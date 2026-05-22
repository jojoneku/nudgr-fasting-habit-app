# Plan: Photo Food Logging (Attachment + Text → Claude Vision → Log)

**Branch:** `feature/photo-food-logging`  
**Replaces:** barcode scanner (removed)  
**Why:** PH food has no viable barcode DB. A photo + optional text description sent to Claude Haiku vision handles homemade dishes, restaurant plates, and mixed ulam+kanin combos that barcodes can never cover. Text description enables DB candidate lookup so a named product can still resolve to a DB entry.

---

## Goal

User attaches a photo via the camera icon in the existing chat input bar, optionally types a description ("dunkin donut glazed"), and hits send. The app compresses the image, fetches DB candidates from the text (if any), and calls Lambda (`op: estimateMacrosFromPhoto`) with image + text + candidates. Lambda uses Claude Haiku vision to identify food and estimate portions, resolving to a DB entry when a candidate matches or falling back to AI macros when none do. User reviews and confirms on a result sheet.

---

## Resolution Logic

```
photo + text ("dunkin donut")
  → FTS search on text → candidate pool from local DB
  → Lambda (image + text + candidates)
      → food_id matched  → EstimationSource.db   (accurate DB macros)
      → no match         → EstimationSource.cloudAi (Haiku estimate)

photo alone (no text)
  → no candidate pool
  → Lambda (image only)
      → always EstimationSource.cloudAi (Haiku estimates portions visually)
```

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lambda_function.py` | Modify — add `estimateMacrosFromPhoto` op | Backend |
| `lib/services/ai_coach_service.dart` | Modify — add abstract `estimateMacrosFromPhoto` | Service |
| `lib/services/cloud_ai_coach_service.dart` | Modify — implement `estimateMacrosFromPhoto` | Service |
| `lib/services/null_ai_coach_service.dart` | Modify — stub returning `null` | Service |
| `lib/services/on_device_ai_coach_service.dart` | Modify — stub returning `null` | Service |
| `lib/presenters/nutrition_presenter.dart` | Modify — add `attachedPhoto`, `analyzePhotoMessage`, `logPhotoMeal` | Presenter |
| `lib/views/nutrition/photo_result_sheet.dart` | **Create** | View |
| `lib/views/nutrition/nutrition_screen.dart` | Modify — camera attach button + photo thumbnail in input bar | View |
| `pubspec.yaml` | Modify — add `image_picker` | Config |

---

## Interface Definitions

### Lambda — new op

**Request:**
```json
{
  "op": "estimateMacrosFromPhoto",
  "payload": {
    "image_base64": "<base64 JPEG>",
    "text": "dunkin donut glazed",
    "candidates": [
      { "food_id": "ph_dunkin_glazed", "name": "Dunkin Donuts Glazed Donut" }
    ]
  }
}
```
`text` and `candidates` are optional (both absent for photo-only sends).

**Success response** — same schema as `parseFoodWithCandidates`:
```json
{
  "intent": "single_dish" | "items_list",
  "items": [
    {
      "name": "Glazed Donut",
      "grams": 57,
      "hyde": "glazed yeast donut, fried, sugar-coated",
      "food_id": "ph_dunkin_glazed",
      "confidence": 0.91,
      "estimated_macros": null
    }
  ]
}
```

**Error response** — new `error` field for bad-image cases:
```json
{ "error": "no_food_detected" | "image_unclear" | "inappropriate_content" }
```
These are returned as HTTP 200 with an `error` key — not 4xx — so the client can show a friendly UI state without treating it as a network failure.

### Bedrock vision message format (Lambda internal)

```python
messages = [{
  "role": "user",
  "content": [
    {
      "type": "image",
      "source": {
        "type": "base64",
        "media_type": "image/jpeg",
        "data": payload["image_base64"]
      }
    },
    { "type": "text", "text": prompt }
  ]
}]
```

### Lambda prompt strategy

**Guard prompt (first, cheap):** Before the main inference, run a fast pre-check:
```
"Does this image contain food or a food package? 
 Does it contain nudity, violence, or other inappropriate content?
 Reply with ONLY: {"has_food": true/false, "is_inappropriate": true/false}"
```
- `is_inappropriate: true` → return `{"error": "inappropriate_content"}` immediately, no further inference
- `has_food: false` → return `{"error": "no_food_detected"}` immediately

**Main prompt (after guard passes):**
```
Identify all food items visible in this image.
[If text hint provided]: The user says this is: "{text}"
[If candidates provided]: Match against these DB entries when confident:
  {candidates}

For EACH food item:
  - name: short food name
  - grams: estimated weight in grams — use visual cues:
      • standard dinner plate ≈ 25cm diameter ≈ 150–300g of rice/viand
      • a cup of cooked rice ≈ 180g; 1 egg ≈ 50g; 1 piece chicken thigh ≈ 110g
      • cutlery, hands, cups in frame as scale references
      • standard serving sizes when portion is not visible (e.g. 1 donut ≈ 57g)
  - hyde: descriptive phrase for search (e.g. "cooked white rice, steamed, plain")
  - food_id: matched candidate id, or null
  - confidence: 0.0–1.0 for food_id pick (0.0 when null)
  - estimated_macros: {calories, protein_g, carbs_g, fat_g} for the whole item
                      — REQUIRED when food_id is null, null when food_id is set

If image is too blurry or unclear to identify food with confidence, reply ONLY:
{"error": "image_unclear"}

Reply with ONLY valid JSON matching this schema:
{"intent": "single_dish"|"items_list", "items": [...]}
```

### Service abstract

```dart
// AiCoachService — new method
Future<PhotoFoodResult> estimateMacrosFromPhoto({
  required String base64Image,
  String text = '',
  List<FoodSearchCandidate> candidates = const [],
});

// Return type — new sealed class (see Models section)
// NullAiCoachService + OnDeviceAiCoachService → return PhotoFoodResult.unavailable()
// CloudAiCoachService → _call('estimateMacrosFromPhoto', {...}) and parse
```

### New model — `PhotoFoodResult`

```dart
// lib/models/photo_food_result.dart
sealed class PhotoFoodResult {
  const PhotoFoodResult();
  factory PhotoFoodResult.success(ParseFoodResult data) = PhotoFoodSuccess;
  factory PhotoFoodResult.error(PhotoFoodError kind) = PhotoFoodFailure;
  factory PhotoFoodResult.unavailable() = PhotoFoodUnavailable;
}

class PhotoFoodSuccess extends PhotoFoodResult {
  final ParseFoodResult data; // reuses existing model — items + intent
  const PhotoFoodSuccess(this.data);
}

class PhotoFoodFailure extends PhotoFoodResult {
  final PhotoFoodError kind;
  const PhotoFoodFailure(this.kind);
}

class PhotoFoodUnavailable extends PhotoFoodResult {
  const PhotoFoodUnavailable();
}

enum PhotoFoodError {
  noFoodDetected,   // Lambda: "no_food_detected"
  imageUnclear,     // Lambda: "image_unclear"
  inappropriate,    // Lambda: "inappropriate_content"
  networkError,     // HTTP failure / timeout
}
```

### Presenter public API

```dart
// Attachment state — lives in NutritionPresenter
XFile? get attachedPhoto;           // non-null when user has attached a photo
bool   get isPhotoAnalyzing;        // true while Lambda call is in-flight

void   attachPhoto(XFile photo);    // called from camera/gallery picker
void   clearAttachedPhoto();        // called when user removes the thumbnail

// Called instead of the normal _sendChat path when attachedPhoto != null
Future<void> sendMessageWithPhoto(String text);
//   1. Fetches DB candidates using text (if non-empty) via existing FTS path
//   2. Compresses image to ≤1024px JPEG q=80
//   3. Calls cloudAi.estimateMacrosFromPhoto(image, text, candidates)
//   4. On PhotoFoodSuccess → opens PhotoResultSheet via a callback/stream
//   5. On PhotoFoodFailure/Unavailable → shows appropriate inline error in chat

Future<void> logPhotoMeal(List<ExtractedFoodItem> items);
//   Identical pipeline to parseFoodWithCandidates logging path:
//   build FoodEntry per item (EstimationSource.db OR .cloudAi per resolvedFoodId),
//   prepend "📷" prefix to chat message rawText,
//   persist, _learnFromEntry, _updateLogStreak, _checkGoalMet, etc.
```

**Note on UI callback:** `sendMessageWithPhoto` needs to trigger `PhotoResultSheet` from the presenter. Use a `Stream<PhotoFoodSuccess>` or `ValueNotifier<PhotoFoodSuccess?>` on the presenter that the View listens to, to avoid passing `BuildContext` into the presenter.

No new `StorageService` keys needed.

---

## UI Changes — `nutrition_screen.dart`

**Input bar additions:**
- Camera `IconButton` (`Icons.camera_alt_outlined`) left of the text field (where barcode was)
  - Tapping opens a bottom sheet with two options: **Camera** / **Gallery** — both via `image_picker`
  - Disabled (greyed, not hidden) when `!presenter.cloudAiAvailable`, tooltip: `'Enable Cloud AI in Settings'`
- **Photo thumbnail strip** — appears between the suggestion strip and the input row when `presenter.attachedPhoto != null`
  - Shows a 56×56 rounded preview of the attached image
  - `×` dismiss button top-right of the thumbnail → calls `presenter.clearAttachedPhoto()`
- Send button behavior: if `attachedPhoto != null` → calls `presenter.sendMessageWithPhoto(text)` instead of normal send

---

## New View — `photo_result_sheet.dart`

Modal bottom sheet triggered by the presenter's result stream after Lambda responds.

**States:**

| State | Trigger | UI |
|---|---|---|
| `PhotoFoodSuccess` (items present) | Lambda returned ≥1 item | Thumbnail + scrollable item list with editable grams + macro chips. "Confirm & Log" + "Discard" buttons |
| `PhotoFoodSuccess` (items empty) | Lambda returned 0 items | "Couldn't identify any food" + "Add manually" button → existing manual-add flow |
| `PhotoFoodFailure.noFoodDetected` | Lambda: `no_food_detected` | "No food found in this photo" + "Try a different photo" + "Add manually" |
| `PhotoFoodFailure.imageUnclear` | Lambda: `image_unclear` | "Photo is too blurry or dark" + "Retake photo" + "Add manually" |
| `PhotoFoodFailure.inappropriate` | Lambda: `inappropriate_content` | "This image can't be used for food logging" (no further detail) + dismiss |
| `PhotoFoodFailure.networkError` | HTTP error / timeout | "Couldn't reach Cloud AI — check connection" + "Retry" + "Add manually" |
| `PhotoFoodUnavailable` | Cloud AI off | Not shown as sheet — inline error in chat bar instead |

**Result item row:**
- Food name (editable inline)
- Gram field (editable, numeric keyboard)
- Macro chips: kcal / P / C / F — recalculate live as grams change
- DB match badge (`DB` chip in `onSurfaceVariant`) vs AI estimate badge (`Cloud` chip in `primary`)
- Trash icon to remove the item from the list

---

## Implementation Order

1. **Lambda** — add `estimateMacrosFromPhoto` to `lambda_function.py`
   - Two-step inference: guard check → main food extraction
   - Reuse `_normalize_parsed_items` for output normalisation
   - Return `{"error": ...}` for bad-image cases
   - Deploy to AWS

2. **pubspec** — add `image_picker: ^1.1.2`

3. **Model** — create `lib/models/photo_food_result.dart`

4. **Service layer**
   - Add abstract `estimateMacrosFromPhoto` to `AiCoachService`
   - Stub in `NullAiCoachService` + `OnDeviceAiCoachService`
   - Implement in `CloudAiCoachService` — parse success/error fields, return typed `PhotoFoodResult`

5. **Presenter** — add `attachedPhoto`, `isPhotoAnalyzing`, `attachPhoto`, `clearAttachedPhoto`, `sendMessageWithPhoto`, `logPhotoMeal`; add `ValueNotifier<PhotoFoodSuccess?>` for result sheet trigger

6. **View: `photo_result_sheet.dart`** — all states above

7. **View: `nutrition_screen.dart`** — camera button, thumbnail strip, modified send path

---

## RPG Impact

- Items with `food_id` → `EstimationSource.db` → `isTrusted = true`
- Items without `food_id` → `EstimationSource.cloudAi` → `isTrusted = true`
- Both count toward XP, streaks, and goal notifications — same as chat-parsed food
- No new XP events needed

---

## Edge Cases & Mitigations

| Case | Where handled | Behaviour |
|---|---|---|
| NSFW / inappropriate image | Lambda guard prompt | Returns `inappropriate_content` → Flutter shows neutral dismissal message, no detail |
| No food in photo (selfie, landscape) | Lambda guard prompt | Returns `no_food_detected` → "No food found" UI state + manual-add escape |
| Blurry / dark / overexposed photo | Lambda main prompt fallback | Returns `image_unclear` → "Too blurry" UI state + retake option |
| Photo with only packaging, no food visible | Lambda main prompt | Haiku identifies product from packaging text — acceptable; user can adjust grams |
| Image too large → payload / timeout | Flutter pre-compress | Resize to ≤1024px longest edge, JPEG q=80; hard-reject if result > 800 KB before encoding |
| Haiku hallucinates a food not in image | Result sheet | Thumbnail visible; user removes wrong items before confirming |
| Text hint present but no DB candidates match | Lambda | Falls back to AI estimate for all items — same as photo-only path |
| Lambda timeout (>30s) | CloudAiCoachService | Catches `TimeoutException` → `PhotoFoodFailure.networkError` |
| User sends photo while fasting + ifSync on | `logPhotoMeal` | IF-Sync gate drops log silently (same as all other food log paths) |
| Cloud AI off / not signed in | Presenter + UI | Camera button greyed; `sendMessageWithPhoto` emits `PhotoFoodUnavailable` → inline chat error, no sheet |
| User attaches photo then clears it mid-type | Presenter | `clearAttachedPhoto()` resets state; normal text send path resumes |
| Two rapid photo sends | Presenter | Guard with `isPhotoAnalyzing` — second send is a no-op while first is in-flight |
| Bedrock Haiku vision unavailable in ap-southeast-1 | Lambda deploy | Verify region support; fall back to `us-east-1` if needed (document in deploy notes) |

---

## Acceptance Criteria

- [ ] Camera icon in input bar opens picker (Camera / Gallery options)
- [ ] Selected photo appears as thumbnail in input bar; `×` removes it
- [ ] Photo alone → Lambda returns AI-estimated items with gram estimates based on visual cues
- [ ] Photo + "dunkin donut" → FTS runs, candidates sent; DB match returns `DB` badge
- [ ] Photo + text with no DB match → AI estimate returned with `Cloud` badge
- [ ] User can edit food name and grams per item; macros recalculate live
- [ ] User can remove individual items from the result list
- [ ] Inappropriate photo → neutral dismissal message, no detail leaked
- [ ] Blurry photo → "Too blurry" state with retake option
- [ ] No-food photo → "No food found" state with manual-add escape
- [ ] Network failure → "Couldn't reach Cloud AI" with retry
- [ ] Camera button greyed (not hidden) when Cloud AI is off
- [ ] Confirmed items logged with `📷` prefix and correct source badge
- [ ] Items count toward daily calorie / macro totals and trigger goal notifications
- [ ] `dart format` passes; `flutter analyze` zero errors
