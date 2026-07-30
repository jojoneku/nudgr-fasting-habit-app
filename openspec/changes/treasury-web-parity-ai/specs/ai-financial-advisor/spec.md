## ADDED Requirements

### Requirement: Advisor runs without the non-finance presenters

The financial advisor SHALL function on a surface that has no fasting and no nutrition presenter, so
a finance-only client can run it without constructing platform services it has no implementation for.

The coach presenter's `fasting` and `nutrition` dependencies SHALL therefore be optional, and the
advisor context SHALL degrade gracefully when they are absent rather than throwing or inventing
values.

> Chosen over extracting a separate advisor presenter. The extraction was originally justified by
> three claimed *compile* blockers on web; measurement disproved all three (see `design.md` D1), and
> what remained was a runtime constraint — constructing `FastingPresenter` initialises
> `NotificationService`, and `NutritionPresenter` needs a sqflite database — which optional
> dependencies clear directly. The extraction would have moved ~400 lines of shipped advisor logic
> to reach the same behaviour, at materially higher regression risk.

#### Scenario: Advisor builds with no fasting presenter
- **WHEN** the coach presenter is constructed with no fasting and no nutrition presenter
- **THEN** it builds, and the advisor session opens without error

#### Scenario: Absent fasting state degrades honestly
- **WHEN** the advisor assembles its context on a surface with no fasting presenter
- **THEN** it reports "not fasting", omits the elapsed-fast figure, and omits the fasting goal
- **AND** it never substitutes a default goal or fabricates a fast in progress

#### Scenario: Mobile is unaffected
- **WHEN** the coach presenter is constructed with its full set of presenters on mobile
- **THEN** every entry point behaves exactly as before

### Requirement: One advisor implementation across platforms

Mobile and web SHALL run the same advisor presenter and the same chat implementation. Neither
platform SHALL carry a parallel copy.

#### Scenario: Shared presenter
- **WHEN** the advisor runs on either platform
- **THEN** it is the same presenter class, differing only in which optional dependencies and which
  AI service were injected

#### Scenario: Shared chat body, platform-appropriate container
- **WHEN** the advisor chat is shown on mobile and on web
- **THEN** both render the same chat widget — header, message list, advisor log card, input bar —
  with mobile wrapping it in a draggable bottom sheet and web in a docked panel

#### Scenario: Full feature set in both containers
- **WHEN** the advisor chat is shown in either container
- **THEN** conversation history, the advisor-memory editor, and the confirm-before-commit log cards
  are all available

#### Scenario: Chat surface tolerates a narrow container
- **WHEN** the chat is rendered in a container narrower than a phone sheet, such as the web dock
- **THEN** its header and controls lay out without overflowing, the title giving way before the
  actions

### Requirement: Service tier is injected, never assumed

The advisor SHALL take its AI service by injection and SHALL NOT construct an on-device model
service on a platform that has no on-device tier.

#### Scenario: Web supplies cloud only
- **WHEN** the web composition root builds the advisor
- **THEN** it injects an explicit unavailable primary service plus the cloud service as fallback, so
  the presenter never enters its on-device initialisation path

#### Scenario: No dead-end download prompt
- **WHEN** no AI tier is available on a platform with no on-device model
- **THEN** the chat surface explains that the advisor is unavailable and what gates it, rather than
  offering a model download the platform cannot perform

### Requirement: Advisor data and backend are unchanged

Making the advisor platform-agnostic SHALL be behaviour-preserving. Storage keys, sync domains, the
advisor-memory model, and the backend operation SHALL be unchanged, so existing conversations and
memory continue to load with no migration.

#### Scenario: Existing conversations survive
- **WHEN** a user with saved advisor conversations and memory opens the advisor after this change
- **THEN** their conversation history and learned profile load unchanged

#### Scenario: No backend change
- **WHEN** the advisor calls the cloud service
- **THEN** it uses the existing advisor operation and model tier, with no new endpoint or parameter

#### Scenario: History follows the user across platforms
- **WHEN** a conversation is held on one platform and the advisor is opened on the other
- **THEN** the history and memory are the same, having ridden the existing sync domains
