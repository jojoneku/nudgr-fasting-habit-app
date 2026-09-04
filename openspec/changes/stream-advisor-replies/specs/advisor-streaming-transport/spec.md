## ADDED Requirements

### Requirement: Advisor turns are delivered incrementally
The `adviseFinance` op SHALL deliver its reply as a sequence of text deltas over a single long-lived HTTP response, beginning as soon as the model produces its first tokens. The transport MUST NOT buffer the complete reply before sending. Time to first byte SHALL be independent of total reply length.

#### Scenario: First text arrives well before the reply is complete
- **WHEN** the advisor answers a question that takes 40 seconds to generate in full
- **THEN** the first text delta reaches the client within a few seconds and further deltas follow as they are produced

#### Scenario: A long reply is no longer a failure
- **WHEN** an advisor turn takes 43 seconds end to end
- **THEN** the reply is delivered in full and the user never sees a server-error message

#### Scenario: Short replies are unaffected
- **WHEN** the advisor answers in one short sentence
- **THEN** the reply renders as a single delta followed by the terminating frame, with no visible difference from a buffered reply

### Requirement: Advisor transport is separate from the shared coach API
The advisor SHALL be reached at its own endpoint, configured independently of the endpoint used by the other coach ops. The remaining ops (`respond`, `classifyFinance`, `parseFoodFromImage`, `parseFoodWithCandidates`) MUST continue to use the existing HTTP API unchanged.

#### Scenario: Only the advisor moves
- **WHEN** the app performs a chat-logging category classification
- **THEN** the request goes to the existing coach API, not to the advisor endpoint

#### Scenario: Advisor endpoint absent from a build
- **WHEN** a build ships without the advisor endpoint configured
- **THEN** the advisor falls back to the existing buffered path rather than reporting the feature as unavailable

### Requirement: A streamed turn terminates with a metadata frame
Every successful streamed turn SHALL end with a single terminating frame carrying the structured tail of the turn: the tool calls the model requested, the assistant turn verbatim for replay, whether the reply hit its token ceiling, and the usage counters. A stream that ends without this frame MUST be treated as a failed turn.

#### Scenario: Ordinary answer terminates cleanly
- **WHEN** the advisor answers without requesting tools
- **THEN** the terminating frame reports no tool calls and the accumulated deltas are the complete reply

#### Scenario: Tool request arrives in the terminating frame
- **WHEN** the advisor requests a tool call
- **THEN** the terminating frame carries the tool calls and the verbatim assistant content, and the client's tool loop proceeds from it

#### Scenario: Truncation is reported, not inferred
- **WHEN** the reply stops because it reached the token ceiling
- **THEN** the terminating frame reports truncation and the client appends the truncation notice

#### Scenario: Missing terminating frame is an error
- **WHEN** the connection closes after some text deltas but before a terminating frame
- **THEN** the client treats the turn as failed rather than as a complete short answer

### Requirement: Partial replies survive a mid-stream failure
When a stream fails after delivering text, the client SHALL keep the text already shown and offer to retry. It MUST NOT discard partial prose in favour of an error state, and it MUST NOT present a partial reply as a finished answer.

#### Scenario: Connection drops mid-answer
- **WHEN** the stream dies after three paragraphs
- **THEN** those paragraphs remain on screen, marked as unfinished, with a retry affordance

#### Scenario: Partial reply is not mistaken for complete
- **WHEN** a turn ends without its terminating frame
- **THEN** the message is not marked as a finished assistant turn and is excluded from replay as a completed turn

#### Scenario: Failure before any text
- **WHEN** the stream fails before the first delta
- **THEN** the client reports the failure the way it reports a failed buffered turn today

### Requirement: The advisor endpoint authenticates every request itself
Because the advisor endpoint has no gateway authorizer, the function SHALL verify the caller's Supabase access token itself — signature, expiry, and issuer — before performing any model invocation, and SHALL derive the user identity used for rate limiting from the verified token. Requests without a valid token MUST be rejected with 401.

#### Scenario: Valid token is accepted
- **WHEN** a signed-in user's request carries a current access token
- **THEN** the token verifies, the user id comes from its claims, and the turn proceeds

#### Scenario: Missing or malformed token
- **WHEN** a request arrives with no bearer token
- **THEN** the endpoint returns 401 and never calls the model

#### Scenario: Expired or wrongly-signed token
- **WHEN** a request carries an expired token, or one signed by a key outside the project's key set
- **THEN** the endpoint returns 401 and never calls the model

#### Scenario: Rejection is cheap
- **WHEN** an unauthenticated request arrives
- **THEN** it is rejected without incurring model cost or consuming the caller's daily allowance

### Requirement: Browser calls to the advisor endpoint are permitted explicitly
The advisor endpoint SHALL permit browser calls from the app's deployed web origins, naming the `authorization` and `content-type` headers explicitly rather than relying on a wildcard. The configuration SHALL be asserted against the live endpoint by an automated check, not assumed from a template.

#### Scenario: Deployed web origin can call the advisor
- **WHEN** the Treasury web app calls the advisor from a deployed origin
- **THEN** the preflight succeeds and the streamed response is readable

#### Scenario: Misconfiguration fails the deploy
- **WHEN** the live endpoint's allowed headers or origins do not match the expected configuration
- **THEN** the automated check fails and the deploy surfaces it

#### Scenario: Streaming survives the browser path
- **WHEN** a browser reads the advisor response
- **THEN** deltas are readable as they arrive rather than only after the response completes

### Requirement: Streaming does not change what a turn costs the user
A streamed turn SHALL consume exactly one unit of the caller's daily allowance, metered once per user-initiated turn even when the turn resolves through several model invocations in a tool loop. Exceeding the allowance MUST be reported before streaming begins, not partway through.

#### Scenario: One streamed turn costs one unit
- **WHEN** a user question resolves through three streamed model invocations in a tool loop
- **THEN** the daily count increases by one

#### Scenario: Over the cap, nothing streams
- **WHEN** a user who has exhausted the daily allowance asks a question
- **THEN** the endpoint reports the limit before any delta is sent, and the client shows the existing limit message
