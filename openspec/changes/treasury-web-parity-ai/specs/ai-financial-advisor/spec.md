## ADDED Requirements

### Requirement: Platform-agnostic advisor presenter

The financial advisor's state, context assembly, conversation store, and learned memory SHALL live
in a presenter whose dependencies are limited to the finance presenters (`TreasuryDashboardPresenter`,
`BudgetPresenter`, `InstallmentPresenter`, `LedgerPresenter`), `StorageService`, and an injected
`AiCoachService`. It SHALL NOT depend on fasting, nutrition, activity, or on-device-model
dependencies.

#### Scenario: Advisor compiles for every target
- **WHEN** the advisor presenter's transitive imports are inspected
- **THEN** they include no notification service, no local food database, no health integration, and
  no on-device model package

#### Scenario: Service is injected, not constructed
- **WHEN** the advisor presenter is created
- **THEN** its AI service arrives by constructor injection, so mobile can supply its tiered service
  and web its cloud service without the presenter knowing the difference

### Requirement: One advisor implementation across platforms

Mobile and web SHALL share a single advisor implementation. The multi-domain coach presenter SHALL
delegate its finance-advisor entry point to the shared advisor presenter rather than carrying a
parallel implementation.

#### Scenario: Mobile delegates
- **WHEN** the Money Mentor entry point is opened on mobile
- **THEN** the conversation is driven by the shared advisor presenter

#### Scenario: Behavior is identical
- **WHEN** the same question is asked against the same Treasury data on either platform
- **THEN** the assembled advisor context and the resulting behaviors are the same

#### Scenario: Other coach entry points are unaffected
- **WHEN** the nutrition, fasting, stats, treasury, or general entry points are opened
- **THEN** they behave exactly as before, still served by the multi-domain coach presenter

### Requirement: Advisor extraction preserves existing data and behavior

Extracting the advisor SHALL be behavior-preserving. Storage keys, sync domains, the advisor-memory
model, and the backend operation SHALL be unchanged, so existing conversations and memory continue
to load with no migration.

#### Scenario: Existing conversations survive
- **WHEN** a user with saved advisor conversations and memory opens the advisor after the extraction
- **THEN** their conversation history and learned profile load unchanged

#### Scenario: Context assembly is unchanged
- **WHEN** the extracted presenter assembles an advisor context for a fixed data fixture
- **THEN** it produces the same context the pre-extraction implementation produced for that fixture

#### Scenario: No backend change
- **WHEN** the extracted advisor calls the cloud service
- **THEN** it uses the existing advisor operation and model tier, with no new endpoint or parameter

### Requirement: Reusable advisor chat body

The advisor's chat UI SHALL be a container-agnostic widget, so each platform can wrap it in the
presentation appropriate to that form factor without duplicating the chat implementation.

#### Scenario: Two containers, one body
- **WHEN** the advisor chat is shown on mobile and on web
- **THEN** mobile wraps the shared body in its draggable bottom sheet and web in a docked panel

#### Scenario: Full feature set in both containers
- **WHEN** the advisor chat is shown in either container
- **THEN** conversation history, the advisor-memory editor, and the confirm-before-commit log cards
  are all available
