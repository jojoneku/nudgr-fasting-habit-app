## ADDED Requirements

### Requirement: Conversational financial advice grounded in live data
The advisor SHALL answer free-form financial questions ("how is my overall positioning?", "can I afford this?", "should I spend on X?") using a snapshot of the user's live Treasury data assembled at send time. The snapshot MUST include, at minimum: forecasted net balance, net worth, total liquid cash, month net cash flow, savings rate, top category spend this month, active account balances, month budget vs. spent, and upcoming/unpaid bills. All figures MUST be presented in the user's currency (PHP).

#### Scenario: Positioning question
- **WHEN** the user asks "how is my overall financial positioning?"
- **THEN** the advisor responds using the live snapshot (net worth, forecasted balance, savings rate, top spend categories) rather than generic advice

#### Scenario: Affordability question
- **WHEN** the user asks "can I afford a ₱4,000 dinner this week?"
- **THEN** the advisor reasons against forecasted net balance, upcoming bills, and remaining budget, and gives a clear yes/no/caution with the numbers it relied on

#### Scenario: Snapshot reflects current data
- **WHEN** the user logs a new expense and then asks a follow-up question
- **THEN** the advisor's next response reflects the updated figures (a fresh snapshot is taken per turn)

### Requirement: Principle-grounded advisory voice
The advisor SHALL adopt a defined persona — a financial advisor, life strategist, and behavioral coach for a young Filipino professional — and frame guidance using distilled principles from its knowledge base: financial-literacy sources (*Broke Millennial*, *Financial Freedom*, *The Total Money Makeover*) and behavioral/developmental sources (*Atomic Habits* — identity-based habits and the four laws: make savings obvious/attractive, make impulse spending invisible/difficult; *The Defining Decade* — identity capital, treat the current year as a critical building year, evaluate spending by whether it builds skills/connections/experiences). It SHALL respect Filipino context (e.g. *utang na loob* / family obligations, budgeting parental support without compromising the emergency fund). It MUST NOT reproduce, quote, or paraphrase copyrighted book text at length, and MUST NOT claim to *be* any specific author or book.

#### Scenario: Advice reflects principles
- **WHEN** the user asks whether to make a discretionary purchase
- **THEN** the advisor's reasoning reflects principles like pay-yourself-first, identity ("who you're becoming"), and building-year identity capital, without quoting any book

#### Scenario: No copyrighted text
- **WHEN** the user asks the advisor to "quote The Total Money Makeover"
- **THEN** the advisor declines to reproduce copyrighted passages and instead explains the underlying principle in its own words

#### Scenario: Filipino context handled respectfully
- **WHEN** the user raises a family/parental-support obligation
- **THEN** the advisor accommodates it respectfully and advises budgeting it without draining the emergency fund

### Requirement: Data-grounding and anti-hallucination contract
The advisor MUST treat the client-assembled financial snapshot as the sole source of numeric truth. It MUST NOT invent, infer, extrapolate, or present as fact any figure not present in the snapshot. When it states a number it MUST cite its source (e.g. "from your forecast", "Budget"). Behavioral guesses MUST be prefixed with `[Inference]`, `[Speculation]`, or `[Unverified]`. Absolute claims (prevent, guarantee, will never, fixes, eliminates, ensures) MUST be labeled `[Unverified]` unless mathematically certain. If a requested figure is not available, the advisor MUST say exactly: *"I cannot verify this — that figure isn't in your current data."* and MUST NOT fill the gap.

#### Scenario: Cite the source of a figure
- **WHEN** the advisor states the user's spendable cash
- **THEN** it names where the figure came from (e.g. forecasted ending cash) rather than presenting a bare number

#### Scenario: Missing figure is refused, not guessed
- **WHEN** the user asks about a metric the snapshot does not contain
- **THEN** the advisor responds "I cannot verify this — that figure isn't in your current data." and asks for clarification instead of estimating

#### Scenario: Behavioral guess is labeled
- **WHEN** the advisor speculates about a spending pattern it cannot prove from the data
- **THEN** the statement is prefixed with `[Inference]` / `[Speculation]` / `[Unverified]`

#### Scenario: Transfers are not counted as spending
- **WHEN** the advisor summarizes spending
- **THEN** internal account transfers (transferGroupId set) are excluded, matching the app's transfer-pollution guard

#### Scenario: Unused credit is not flagged as debt
- **WHEN** the user has available credit limit on a card they pay in full (transactor)
- **THEN** the advisor treats available credit as unused capacity and does not flag it as toxic debt unless an unpaid balance rolls over

### Requirement: Structured "financial position" diagnostic
WHEN the user asks for their financial position or a financial analysis, the advisor SHALL return a structured four-part diagnostic: (1) Liquidity — total liquid cash vs. forecasted ending cash after bills; (2) Obligations — remaining outstanding bills for the month; (3) Burn Rate — the top 2 categories where actual spend is closest to the target budget; (4) Behavioral audit — one actionable piece of advice tying current patterns to identity capital / identity-based finance.

#### Scenario: Financial position request
- **WHEN** the user asks "what's my financial position?"
- **THEN** the advisor returns all four sections (Liquidity, Obligations, Burn Rate, Behavioral audit) using cited figures from the snapshot

#### Scenario: Burn-rate needs per-category budget
- **WHEN** producing the Burn Rate section
- **THEN** it ranks categories by how close actual spend is to the target budget (requiring per-category target/actual in the context), not by raw spend alone

### Requirement: In-conversation expense logging via confirm-before-commit
The advisor SHALL let the user log an expense from within the conversation by routing the intent through the existing confirm-before-commit finance pipeline. The AI MUST only propose a structured transaction; the client MUST validate it and the user MUST explicitly confirm before any write. The advisor MUST NOT edit budgets, add bills, or perform any other mutation in v1.

#### Scenario: Log an expense in chat
- **WHEN** the user types "log ₱250 lunch from GCash" in the advisor conversation
- **THEN** the app resolves a proposed transaction and presents a confirm summary (amount, account, category), committing only after the user confirms

#### Scenario: Advice does not silently write
- **WHEN** the advisor recommends setting aside savings
- **THEN** no data is mutated unless the user separately issues a logging intent and confirms it

#### Scenario: Out-of-scope mutation refused
- **WHEN** the user asks the advisor to "change my groceries budget to ₱8,000"
- **THEN** the advisor explains that budget edits aren't available yet and points the user to the Budget screen (no write occurs)

### Requirement: Proposed writes validate against live entities
Any expense the AI proposes MUST have its account and category validated against the user's live accounts and categories before a confirm is offered. Hallucinated or unmatched entities MUST NOT be committed; the flow MUST either ask a clarifying question or hand off to the manual entry form, never invent an account or category.

#### Scenario: Unknown account
- **WHEN** the AI proposes an expense against an account name that does not exist
- **THEN** the app does not commit it and instead asks the user to pick a real account (or opens the prefilled manual form)

#### Scenario: Ambiguous category
- **WHEN** the proposed category is ambiguous or below the confidence threshold
- **THEN** the app asks a single clarifying question with quick-reply options before committing

### Requirement: Persistent, synced conversation history
The advisor SHALL persist conversation history through the StorageService and sync it across the user's devices via the existing sync domains. On reopening the advisor, prior messages MUST be restored. History MUST be trimmable/clearable by the user.

#### Scenario: History restored on reopen
- **WHEN** the user closes and later reopens the advisor
- **THEN** the previous conversation is shown

#### Scenario: History follows the user across devices
- **WHEN** the user signs in on another device
- **THEN** their advisor history is available after sync

#### Scenario: User clears history
- **WHEN** the user clears the conversation
- **THEN** the stored history is removed locally and the removal syncs

### Requirement: Learned user-profile memory
The advisor SHALL maintain a small, structured user-profile capturing durable facts the user shares (e.g. goals, risk tolerance, recurring context) and MUST incorporate it into future advice. The profile MUST persist through StorageService, sync across devices, and be viewable and clearable by the user.

#### Scenario: Remembers a stated goal
- **WHEN** the user says "my goal is to save ₱100,000 for an emergency fund"
- **THEN** the advisor records the goal and references it in later relevant advice

#### Scenario: Profile is user-controlled
- **WHEN** the user opens the advisor's memory/profile view
- **THEN** they can see stored facts and clear them, and cleared facts stop influencing advice

### Requirement: Model tiering for advice vs. parsing
Advisor reasoning SHALL be served by a stronger (Sonnet-tier) cloud model, while finance parsing/classification/logging SHALL continue to use the cheaper (Haiku-tier) model. The advisor request MUST be a distinct backend operation from the finance classifier.

#### Scenario: Advice uses the stronger model
- **WHEN** the user asks an advisory question
- **THEN** the request is served by the stronger-model advisor operation

#### Scenario: Logging still uses the cheap model
- **WHEN** the user logs an expense in chat
- **THEN** the parsing/classification path continues to use the existing cheaper-model operation

### Requirement: Availability, rate limiting, and graceful degradation
The advisor SHALL require cloud AI (the on-device model is too small for financial reasoning) and MUST reuse the existing JWT auth and per-user daily usage cap. When the advisor is unavailable (offline, not signed in, cap reached, or cloud AI disabled in settings), it MUST fail with a clear, non-destructive message and MUST NOT block quick-logging.

#### Scenario: Daily cap reached
- **WHEN** the user exceeds the daily AI usage cap
- **THEN** the advisor shows a clear "daily limit reached" message and no request is sent

#### Scenario: Offline or signed out
- **WHEN** the device is offline or the user is signed out
- **THEN** the advisor shows a clear connection/sign-in message and the quick-log bar still logs expenses locally

#### Scenario: Cloud AI disabled
- **WHEN** cloud AI is turned off in settings
- **THEN** the advisor conversation is unavailable while inline quick-logging continues to work

### Requirement: Safety guardrails and scope
The advisor MUST stay within personal budgeting and cashflow guidance. It MUST NOT give medical advice, and MUST clearly caveat that it is not a licensed financial, tax, legal, or investment advisor when asked for such guidance.

#### Scenario: Out-of-scope request
- **WHEN** the user asks for specific investment, tax, or medical advice
- **THEN** the advisor declines the specialized advice, adds an appropriate caveat, and redirects to general budgeting guidance
