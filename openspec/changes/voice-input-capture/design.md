## Context

The ledger chat bar (`lib/views/treasury/ledger/ledger_view.dart`) and the food
composer (`lib/views/nutrition/widgets/log_composer_sheet.dart`) each own a text
field that feeds an existing parse pipeline (`finance_nlp_parser` →
`LedgerPresenter`; `NutritionPresenter.parseChat`). Both already render a
circular trailing button styled as the reference's mic; today it just submits.

Constraints: MVP architecture (no logic in `build()`, I/O behind services,
constructor injection), dual theme, the combined worktree also builds **Flutter
web** (must not break), and touch targets ≥44px.

## Goals / Non-Goals

**Goals:**
- One reusable, injected speech service used by both inputs.
- Voice produces text that flows through the **unchanged** parse pipelines.
- Visible listening state; transcript is editable, never auto-submitted.
- Graceful permission-denied / unsupported fallback; no dead control.

**Non-Goals:**
- No changes to parsing, models, storage, or RPG math.
- No cloud STT, streaming, wake-word, or TTS read-back.

## Decisions

- **Package: `speech_to_text`.** On-device platform STT (iOS `SFSpeechRecognizer`,
  Android `SpeechRecognizer`, browser `SpeechRecognition`). Free, private, no
  backend. *Alternatives:* cloud STT (rejected — needs backend + network + cost
  for a feature that must feel instant); `record` + custom model (rejected —
  overkill).
- **`SpeechInputService` in `lib/services/`, constructor-injected** into the two
  widgets/presenters. Wraps init/permission/listen/stop and exposes a simple
  `Stream`/callback of partial + final transcripts and a status enum
  (`unavailable`, `denied`, `listening`, `idle`). Keeps `flutter_local`/platform
  concerns out of the views. *Alternative:* call the plugin directly in widgets
  (rejected — violates the services/injection rule and duplicates logic twice).
- **Transcript → existing `TextEditingController`.** The service never submits;
  it writes into the same controller the user types in, so the existing
  send/parse path is literally unchanged. *Alternative:* a dedicated voice-parse
  path (rejected — duplicates the pipeline and risks drift).
- **No auto-submit.** Final transcript stays editable (STT mis-hears amounts and
  merchants); the user confirms with the existing send action.
- **Web-safe.** `speech_to_text` has a web implementation, so no conditional
  imports are required; unsupported environments report `unavailable` and the
  mic is hidden/disabled.

## Risks / Trade-offs

- [STT mis-transcribes amounts/accounts] → transcript is editable and re-uses
  the same forgiving `finance_nlp_parser`; nothing is committed without review.
- [Permission prompt friction / denial] → request lazily on first mic tap; on
  denial show a one-line message and keep text input fully working.
- [Web/Safari speech support is inconsistent] → treat as `unavailable` and hide
  the mic; typed input is the guaranteed path. Mobile is the primary target.
- [Plugin adds native deps / build weight] → `speech_to_text` is widely used and
  lightweight; verify iOS/Android/web builds after adding.

## Migration Plan

1. Add `speech_to_text` to `pubspec.yaml`; `flutter pub get`.
2. Add mic permission strings to iOS `Info.plist` and `AndroidManifest.xml`.
3. Add `SpeechInputService`; inject into the ledger bar and food composer.
4. Wire mic → listening state → transcript into the existing controllers.
5. Verify Android, iOS, and web builds; `flutter analyze` + `dart format` clean.

Rollback: remove the mic wiring + service; the inputs revert to typed-only. No
data or schema is touched, so rollback is safe at any point.

## Open Questions

- Locale: default to device locale, or pin `en`/`fil`? (Lean: device locale,
  fall back to `en_US`.)
- Should a long silence auto-stop capture, or only manual stop? (Lean: use the
  plugin's built-in pause/timeout, plus manual stop.)
