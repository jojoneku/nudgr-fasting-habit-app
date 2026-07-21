## Why

Both the ledger chat bar and the food-logger composer already parse free-form
text into transactions / food entries, and the Nudgr reference draws a **mic
affordance** on those input bars — but it is currently a decorative send button.
Speaking a transaction or meal ("spent 285 on jollibee gcash", "two eggs and
rice") is faster and more natural on mobile than typing, especially one-handed.
This change finally implements that mic.

## What Changes

- Add on-device **speech-to-text** and wire the existing mic affordance on:
  - the ledger chat input bar (`ledger_view.dart`), and
  - the food-logger composer (`log_composer_sheet.dart`).
- Tapping the mic starts listening (with a visible listening state + partial
  transcript); the final transcript is placed into the existing text field and
  flows through the **existing** parse pipelines unchanged
  (`finance_nlp_parser` for the ledger, `NutritionPresenter.parseChat` for food).
- Request microphone permission on first use, with a graceful denied/unavailable
  fallback (input stays typed-text only; no dead button).
- Works on mobile (iOS/Android) and, where the browser supports it, on web.

## Capabilities

### New Capabilities
- `voice-input`: Capture spoken input via on-device speech-to-text and feed the
  transcript into the ledger and food-logging text-parse pipelines, including
  the listening UI, permission handling, and unavailable/denied fallbacks.

### Modified Capabilities
<!-- None: the ledger and food-logging parse behaviors are unchanged; voice only
     produces the same text those pipelines already accept. -->

## Non-goals

- No new transaction/food **parsing** logic — voice reuses the existing text
  pipelines verbatim. Improving parse accuracy is out of scope.
- No cloud/streaming speech services, no custom wake-word, no always-listening.
- No voice **output** (TTS) or read-back.
- No voice control of navigation or other screens beyond these two inputs.

## Impact

- **Dependency**: add `speech_to_text` (on-device platform STT; has web support).
- **Permissions**: microphone usage strings — `NSMicrophoneUsageDescription`
  (+ `NSSpeechRecognitionUsageDescription`) in iOS `Info.plist`; `RECORD_AUDIO`
  in `AndroidManifest.xml`.
- **Code**: a small `SpeechInputService` (services/, injected), listening state
  on the two input widgets/presenters; no changes to parsers, models, or storage.
- **Platforms**: mobile primary; web best-effort (Chrome), silent fallback where
  unsupported. Must not break the Flutter web build.
