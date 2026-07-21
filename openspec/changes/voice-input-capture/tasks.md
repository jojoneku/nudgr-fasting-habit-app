## 1. Dependency & platform setup

- [ ] 1.1 Add `speech_to_text` to `pubspec.yaml`; run `flutter pub get`
- [ ] 1.2 Add iOS mic strings to `Info.plist` (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`)
- [ ] 1.3 Add `RECORD_AUDIO` to `AndroidManifest.xml`
- [ ] 1.4 Confirm Android, iOS, and web builds still compile

## 2. Speech service (I/O behind an interface)

- [ ] 2.1 Add `SpeechInputService` in `lib/services/` wrapping init/permission/listen/stop, exposing partial+final transcript callbacks and a status enum (`unavailable`/`denied`/`listening`/`idle`)
- [ ] 2.2 Unit/logic test the status transitions with a fake plugin (available→listening→final; denied; unavailable)

## 3. Ledger voice input

- [ ] 3.1 Inject `SpeechInputService` into the ledger input bar; add listening state
- [ ] 3.2 Wire mic tap → start/stop capture → write final transcript into the existing ledger `TextEditingController` (no auto-submit)
- [ ] 3.3 Show listening state on the mic control; hide/disable when `unavailable`; show a one-line message on `denied`
- [ ] 3.4 Widget test: activating voice fills the field and the existing submit path parses it

## 4. Food-logger voice input

- [ ] 4.1 Inject `SpeechInputService` into the composer; reuse the same listening UI pattern
- [ ] 4.2 Wire mic tap → transcript into the composer input (no auto-submit); same fallbacks
- [ ] 4.3 Widget test: activating voice fills the composer input

## 5. Verify

- [ ] 5.1 `dart format` + `flutter analyze` clean on changed files
- [ ] 5.2 Full test suite green
- [ ] 5.3 Manual smoke on a device: speak a transaction and a meal; confirm transcript is editable and parses on submit; confirm web build unaffected
