## ADDED Requirements

### Requirement: Voice capture on the ledger and food-logger inputs

The system SHALL present a microphone control on the ledger chat input bar and
on the food-logger composer input, and SHALL, when activated, transcribe the
user's speech on-device and place the resulting text into that input's text
field so it flows through the existing text-parse pipeline unchanged.

#### Scenario: Speaking a ledger transaction

- **WHEN** the user taps the mic on the ledger input bar and says "spent two
  hundred eighty five on jollibee gcash"
- **THEN** the transcribed text is placed in the ledger input field and, on
  submit, is parsed by the existing `finance_nlp_parser` pipeline exactly as if
  the user had typed it

#### Scenario: Speaking a food entry

- **WHEN** the user taps the mic on the food-logger composer and says "two eggs
  and a cup of rice"
- **THEN** the transcribed text is placed in the composer input and is parsed by
  the existing `NutritionPresenter.parseChat` pipeline exactly as if typed

### Requirement: Visible listening state and editable transcript

The system SHALL show a clear listening state while recording (distinct mic
state and, where available, the live partial transcript), and SHALL leave the
final transcript in the editable text field for review/correction before submit
rather than auto-submitting.

#### Scenario: Listening indicator

- **WHEN** speech capture is active
- **THEN** the mic control reflects an active/listening state and the user can
  stop capture by tapping it again

#### Scenario: Transcript is editable, not auto-sent

- **WHEN** capture ends with a final transcript
- **THEN** the text appears in the input field and is NOT auto-submitted; the
  user reviews/edits and submits with the existing send action

### Requirement: Microphone permission and unavailable fallback

The system SHALL request microphone permission on first use and SHALL degrade
gracefully when speech capture is denied or unavailable, keeping typed-text
input fully functional with no dead control.

#### Scenario: Permission denied

- **WHEN** the user denies microphone permission
- **THEN** the app shows a brief, non-blocking message explaining voice is
  unavailable and the input remains usable as a normal text field

#### Scenario: Platform does not support speech capture

- **WHEN** the current platform/browser has no speech-to-text support
- **THEN** the mic control is hidden or disabled and no error is thrown; typed
  input continues to work
