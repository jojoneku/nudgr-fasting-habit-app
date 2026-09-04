## MODIFIED Requirements

### Requirement: Daily rate limiting
Bedrock usage SHALL be metered once per user-initiated turn rather than once per model invocation, so that a multi-hop tool conversation consumes one unit of the daily cap. The cap value itself is unchanged.

Metering now happens before the first delta of a streamed turn, so a user over the cap is told so instead of watching a reply begin and then stop. The user identity the count is keyed to comes from the token the advisor endpoint verified itself, rather than from gateway authorizer claims.

#### Scenario: Multi-hop turn costs one unit
- **WHEN** a single user question resolves through three model invocations in a tool loop
- **THEN** the daily usage count increases by one, not three

#### Scenario: Cap still enforced
- **WHEN** a user exceeds the daily cap
- **THEN** the request returns 429 as it does today

#### Scenario: Cap is reported before streaming starts
- **WHEN** a user over the cap asks the advisor a question
- **THEN** the limit is reported before any text delta is sent, and no partial reply appears

## ADDED Requirements

### Requirement: The reply renders as it is written
An advisor answer SHALL appear progressively in the conversation as the model produces it, using the same in-progress rendering the general coach chat already uses. The user MUST NOT wait on an idle spinner for the whole of a long answer.

#### Scenario: Long answer starts appearing immediately
- **WHEN** the advisor begins a multi-section answer
- **THEN** the first prose appears within a few seconds and grows until the turn completes

#### Scenario: Completed turn settles
- **WHEN** the turn completes
- **THEN** the message is marked finished and stops showing in-progress affordances

#### Scenario: Sheet dismissed mid-answer
- **WHEN** the user closes the chat while a reply is still streaming
- **THEN** rendering stops without error and no further state updates are applied

### Requirement: A turn is not bounded by a gateway timeout
An advisor turn SHALL be allowed to run to the function's own time budget. No turn that the model completes within that budget may be reported to the user as a server error.

#### Scenario: Turn beyond the old ceiling succeeds
- **WHEN** an advisor turn takes 40 seconds
- **THEN** the user receives the complete answer

#### Scenario: Turn beyond the function budget fails honestly
- **WHEN** a turn cannot finish within the function's time budget
- **THEN** the partial prose is kept, the turn is marked unfinished, and a retry is offered

### Requirement: The tool loop resolves from the end of the stream
When the advisor requests tool calls, the client's tool loop SHALL proceed from the terminating frame of the streamed turn, replaying the assistant turn verbatim. Prose written alongside tool calls MUST be shown before the tools run, so the user is not left watching an idle spinner.

#### Scenario: Prose alongside tool calls is shown first
- **WHEN** the advisor writes an explanation and requests a tool call in the same turn
- **THEN** the explanation is displayed before the tool executes

#### Scenario: Replay stays verbatim
- **WHEN** the loop sends the next hop
- **THEN** the assistant turn is replayed exactly as the model produced it, preserving the identifiers the tool results pair with

#### Scenario: Hop limit still applies
- **WHEN** the loop reaches its hop limit with a tool call still pending
- **THEN** it reports that it could not finish rather than presenting the last partial thought as an answer
