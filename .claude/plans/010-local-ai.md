# Plan 010 — Local AI Meal Estimation

**Status:** Ready to implement
**Branch:** `feat/calorie-counting-alchemy-lab` (same as 007)
**Depends on:** Plan 007 (calorie counting v2) — stub already in place
**Research:** Background agent completed 2026-03-22

---

## Decision

**Package:** [`flutter_gemma`](https://pub.dev/packages/flutter_gemma) v0.9.0
**Model:** `FunctionGemma 270M INT4` (.task file, ~300MB download, ~125–200MB RAM)
**Why:** Best Flutter DX, MediaPipe/LiteRT-LM runtime, purpose-built for function calling, structured JSON output via `FunctionCallParser`, actively maintained by Google Developer Expert, smallest viable model that handles instruction following reliably.

**Runner-up:** `fllama` (Qwen 0.5B Q4) — strongest JSON schema guarantee (grammar-constrained decoding), but more complex build setup (specific CMake/NDK versions). Revisit if FunctionGemma accuracy is insufficient.

**Do not use:** `flutter_local_ai` (iOS 26+ / flagship-Android-only gate makes it unshippable to general users), `google_mlkit_text_recognition` (OCR only, wrong tool).

---

## Layers Affected

| Layer | Change |
|---|---|
| Model | `AiMealEstimate` + `AiItemEstimate` — already exist |
| Service | `AiEstimationService` — replace stub with real impl |
| Presenter | `NutritionPresenter` — no changes needed (already calls `_ai.estimate()`) |
| View | `log_meal_sheet.dart` — add model download UI; already has `_AiResultCard` |

---

## Step 1 — Add dependency

```yaml
# pubspec.yaml
dependencies:
  flutter_gemma: ^0.9.0
  path_provider: ^2.1.0   # already likely present; needed for model file path
  crypto: ^3.0.3          # SHA-256 verification of downloaded model
```

---

## Step 2 — iOS entitlements

In `ios/Runner/Runner.entitlements` add:

```xml
<key>com.apple.developer.kernel.extended-virtual-addressing</key>
<true/>
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

Also add to `ios/Runner/DebugProfile.entitlements` for dev builds.

---

## Step 3 — Model storage & download

Model file is downloaded to the app's documents directory (not bundled — 300MB asset would inflate install binary).

```
<documents>/ai_models/function_gemma_270m_int4.task
```

**Download URL (Google-hosted):**
`https://storage.googleapis.com/jmstore/kaggleweb/grader/g-function-calling.task`
*(Canonical URL from flutter_gemma FunctionGemma examples — verify in implementation)*

**Verification:** Store expected SHA-256 hash as a constant; verify after download before loading.

---

## Step 4 — `AiEstimationService` real implementation

Replace the stub at `lib/services/ai_estimation_service.dart`:

```dart
class AiEstimationService {
  static const _modelFileName = 'function_gemma_270m_int4.task';
  static const _modelUrl = 'https://...';          // canonical URL
  static const _expectedSha256 = '...';            // hash of verified model

  InferenceModel? _model;
  bool _isDownloading = false;

  // ── State ────────────────────────────────────────────────────────────────
  bool get isModelAvailable => _model != null;
  bool get isDownloading    => _isDownloading;
  String get modelSizeLabel => '~300 MB';

  // ── Init ─────────────────────────────────────────────────────────────────
  Future<void> init() async {
    final file = await _modelFile();
    if (await file.exists() && await _verifySha(file)) {
      await _loadModel(file.path);
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────
  Future<void> downloadModel({void Function(double)? onProgress}) async {
    if (_isDownloading) return;
    _isDownloading = true;
    // ... HTTP download with progress callback to file ...
    // ... verify SHA-256 ...
    // ... _loadModel(file.path) ...
    _isDownloading = false;
  }

  // ── Estimate ──────────────────────────────────────────────────────────────
  Future<AiMealEstimate> estimate(String description) async {
    if (_model == null) throw UnsupportedError('Model not loaded');
    // Build function-calling tool schema:
    // { "name": "log_meal", "parameters": { "items": [{ "name", "calories", "protein", "carbs", "fat" }] } }
    // Call _model.generateAsync(prompt, tools: [schema])
    // Parse via FunctionCallParser, return AiMealEstimate
  }

  // ── Private ───────────────────────────────────────────────────────────────
  Future<void> _loadModel(String path) async {
    await FlutterGemma.instance.initialize();
    _model = await InferenceModel.createFromPath(path, preferredBackend: PreferredBackend.gpu);
  }
  Future<File> _modelFile() async { /* path_provider */ }
  Future<bool> _verifySha(File f) async { /* crypto package */ }
}
```

**Key implementation notes:**
- Call `AiEstimationService.init()` from `AppShell.initState()` (async, non-blocking)
- Load model once; cache `_model` instance — reloading on every call causes 3–5s delays
- Pass file path to `InferenceModel.createFromPath()` — never load bytes into Dart memory (doubles RAM)
- GPU backend first; falls back to CPU if unavailable
- Wrap inference in try/catch; if JSON parse fails, retry with stricter system prompt

---

## Step 5 — View: download UI in `log_meal_sheet.dart`

The existing stub in `LogMealSheet` shows "AI module not installed" when `!presenter.isAiAvailable`.
Add a download button + progress indicator to that state:

```
┌──────────────────────────────────────────┐
│  AI Meal Estimation                      │
│  Describe your meal and get an instant   │
│  calorie estimate — all on device.       │
│                                          │
│  [DOWNLOAD AI MODEL  (~300 MB)]          │
│  ████████░░░░░░░░░░░░  45%              │
└──────────────────────────────────────────┘
```

**Presenter additions:**

```dart
// NutritionPresenter
bool get isAiDownloading => _ai.isDownloading;

Future<void> downloadAiModel() async {
  // calls _ai.downloadModel(onProgress: ...) and notifyListeners() on progress
}
```

---

## Step 6 — Function-calling prompt schema

FunctionGemma expects tools defined as a JSON dict. For calorie estimation:

```json
{
  "name": "log_meal",
  "description": "Log a meal with per-item calorie estimates",
  "parameters": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "name":     { "type": "string" },
            "calories": { "type": "integer" },
            "protein":  { "type": "number" },
            "carbs":    { "type": "number" },
            "fat":      { "type": "number" }
          },
          "required": ["name", "calories"]
        }
      },
      "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
    },
    "required": ["items"]
  }
}
```

User prompt template:
```
Estimate calories for: "{description}"
Break down by individual items. Use typical restaurant/home portions.
```

---

## Step 7 — Verify checklist

- [ ] No logic in View — download trigger goes through presenter
- [ ] Model file cached; SHA-256 verified before first load
- [ ] iOS entitlements added to both `Runner.entitlements` and `DebugProfile.entitlements`
- [ ] `init()` called non-blocking at app startup
- [ ] JSON parse failure falls back gracefully (retry or show error card)
- [ ] `isAiEstimating` spinner shown during inference
- [ ] Touch targets ≥ 44×44px for download button and result actions
- [ ] No crash when model unavailable — `UnsupportedError` caught in presenter

---

## Package versions (as of 2026-03-22)

| Package | Version |
|---|---|
| `flutter_gemma` | 0.9.0 |
| Model runtime | MediaPipe LiteRT-LM (transitioning from GenAI Task) |
| `path_provider` | ^2.1.0 |
| `crypto` | ^3.0.3 |

---

## References

- [flutter_gemma pub.dev](https://pub.dev/packages/flutter_gemma)
- [flutter_gemma GitHub (DenisovAV)](https://github.com/DenisovAV/flutter_gemma)
- [On-Device Function Calling with FunctionGemma (Medium/GDE)](https://medium.com/google-developer-experts/on-device-function-calling-with-functiongemma-39f7407e5d83)
- [On-Device Function Calling in Flutter (Medium/Easy Flutter)](https://medium.com/easy-flutter/on-device-function-calling-in-flutter-using-flutter-gemma-7cf58a92ec15)
- Runner-up: [fllama pub.dev](https://pub.dev/packages/fllama) — grammar-constrained JSON, more complex build
