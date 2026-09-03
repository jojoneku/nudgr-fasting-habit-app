## MODIFIED Requirements

### Requirement: Data-grounding and anti-hallucination contract
The advisor MUST treat the client-assembled financial snapshot as the sole source of numeric truth, cite the source of every figure, label inferences and absolutes, and refuse with the fixed phrase when a figure is absent — all unchanged.

Rule 8 changes. The advisor MAY now propose creating, editing and deleting bills, receivables, set-asides and budgets through tool calls. It still MUST NOT write anything directly, and it MUST NOT state or imply that anything has been saved, added, recorded or logged until a confirmation result has returned for that specific proposal. Transactions and accounts remain outside what it can propose.

#### Scenario: Proposal is not a save
- **WHEN** the advisor proposes a set-aside and the confirm card is still pending
- **THEN** it describes the proposal as pending and does not claim the set-aside exists

#### Scenario: Confirmed write may be stated
- **WHEN** a confirmation result returns reporting a successful write
- **THEN** the advisor may state that the set-aside was added

#### Scenario: Still cannot log transactions directly
- **WHEN** the user asks the advisor to record an expense
- **THEN** it routes to the existing logging pipeline rather than proposing a transaction tool call

### Requirement: Daily rate limiting
Bedrock usage SHALL be metered once per user-initiated turn rather than once per model invocation, so that a multi-hop tool conversation consumes one unit of the daily cap. The cap value itself is unchanged.

#### Scenario: Multi-hop turn costs one unit
- **WHEN** a single user question resolves through three model invocations in a tool loop
- **THEN** the daily usage count increases by one, not three

#### Scenario: Cap still enforced
- **WHEN** a user exceeds the daily cap
- **THEN** the request returns 429 as it does today
