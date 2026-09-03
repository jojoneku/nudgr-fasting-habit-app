## ADDED Requirements

### Requirement: Nudgy proposes finance mutations through tool calls
Nudgy SHALL be able to propose creating, editing and deleting bills, receivables, set-asides (`BudgetedExpense`) and budgets in response to a conversational request. Proposals SHALL be expressed as Bedrock `tool_use` blocks returned by the `adviseFinance` op. The client SHALL execute the tool loop; the Lambda MUST NOT execute any tool, because it has no access to the user's financial data.

#### Scenario: Set-aside created from a budget observation
- **WHEN** the user says "set aside ₱3,000 a month for braces"
- **THEN** Nudgy proposes a recurring set-aside and, on confirmation, it is written through `BillsReceivablesPresenter.addBudgetedExpense`

#### Scenario: A bill is added in conversation
- **WHEN** the user says "add my internet bill, ₱999, due the 15th every month"
- **THEN** Nudgy proposes a recurring bill and, on confirmation, it is written through `BillsReceivablesPresenter.addBill`

#### Scenario: No tool needed
- **WHEN** the user asks a question that requires no mutation ("how did food do last month?")
- **THEN** Nudgy answers with text only and no confirm card is shown

### Requirement: Confirm before commit
A mutating tool call MUST NOT write to storage. It SHALL place the chat in `ChatPhase.reviewing` with a confirm card describing the proposed change. The write SHALL occur only after explicit user confirmation, and SHALL go through the owning presenter's mutator. The `tool_result` returned to the model MUST describe what actually happened, not what was proposed.

#### Scenario: User confirms
- **WHEN** the user confirms a proposed set-aside
- **THEN** the owning presenter's mutator runs, and the tool result reports the write succeeded

#### Scenario: User declines
- **WHEN** the user dismisses a proposed set-aside without confirming
- **THEN** nothing is written, the tool result reports the decline, and Nudgy acknowledges it rather than retrying the same proposal

#### Scenario: Nudgy never claims an unconfirmed save
- **WHEN** a proposal is pending or declined
- **THEN** Nudgy does not state or imply that anything was saved, added, recorded or logged

### Requirement: Mutations target rows resolved by a search tool
Nudgy SHALL have read tools (`findBills`, `findReceivables`, `findSetAsides`, `findBudgets`) that resolve a phrase to matching rows and their ids. Every editing or deleting tool SHALL take an id obtained from a search result. Nudgy MUST NOT construct or guess an id. Search tools SHALL execute without a confirm card, as they mutate nothing.

#### Scenario: Edit resolves the row first
- **WHEN** the user says "change my internet bill to ₱1,299"
- **THEN** Nudgy searches for the bill, and the confirm card names the specific row it matched

#### Scenario: Ambiguous match
- **WHEN** a search returns more than one plausible row
- **THEN** Nudgy asks which one rather than proposing a mutation against a guess

#### Scenario: No match
- **WHEN** a search returns no rows
- **THEN** Nudgy says it could not find the row and proposes nothing

### Requirement: Recurrence scope is chosen by the user, never the model
The tool schemas MUST NOT expose `applyToFuture`. For any mutation of a recurring bill or receivable, the confirm card SHALL present the recurrence scope as an explicit user choice, stating its consequence, and SHALL default to the narrower single-month scope.

#### Scenario: Deleting a recurring bill
- **WHEN** the user confirms deletion of a bill that is part of a recurring series
- **THEN** the card required an explicit scope choice, and defaulted to this month only

#### Scenario: Model cannot widen scope silently
- **WHEN** the user says "cancel my internet bill for good"
- **THEN** the scope still comes from the card control, not from the model's reading of "for good"

### Requirement: The tool loop terminates
The client SHALL stop the loop after a bounded number of hops (initially 5) within a single user turn, and SHALL tell the user the request did not complete rather than continuing silently. A hop returning neither text nor a tool call SHALL end the loop.

#### Scenario: Hop ceiling reached
- **WHEN** a conversation reaches the hop ceiling without resolving
- **THEN** the loop stops and Nudgy says it could not finish, leaving any pending proposal uncommitted

### Requirement: A chat-created savings budget offers its funding set-aside
When a savings budget is created through chat, the confirm card SHALL offer the matching recurring set-aside, consistent with the offer made by `add_budget_sheet.dart` when the same budget is saved from the budget page.

#### Scenario: Parity with the budget page
- **WHEN** the user creates a savings budget through chat
- **THEN** the same set-aside offer appears as when the budget is saved from the budget page
