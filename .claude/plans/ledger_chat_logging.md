# Plan: Chat-based logging for the Finance Ledger

**Branch target:** `feat/ledger-chat-logging` (off `feat/hub-and-treasury-ui-overhaul`)

## 1. Goal

Replace the form-first entry path with a **regex fast-path + multi-turn AI dialog** that asks for what it doesn't understand instead of guessing or failing.

- Easy: `-500 food gcash` → committed instantly, no AI call.
- Slightly fuzzy: `500 gcash hamburger` → AI asks once `Log ₱500 outflow → Food (GCash)? Yes / Edit / Cancel`. Confirm → committed + token learned.
- Genuinely ambiguous: `-500 b food` → AI asks `Did you mean BPI or BDO?` with quick-reply chips. User taps BPI → AI: `Log ₱500 → Food (BPI)?` → Yes → committed.
- Vague: `paid for groceries` → AI: `How much, and from which account?` → user replies → AI proposes a category → confirms → committed.
- Out-of-scope: AI never invents accounts. It can only pick from the existing list. If after 3 turns it still can't resolve, it suggests opening the form prefilled with what's known.

The conversation lives in a **transient drawer** above the input bar. Once committed or cancelled, the drawer collapses and the transaction list (the only persistent feed) updates. Conversation state is **never persisted** — closing/backgrounding the app drops it.

## 2. UX shape

```
┌────────────────────────────────────────────┐
│ Month • date filter chip • summary card    │ ← unchanged
│ Account filter row                         │ ← unchanged
│                                            │
│ [transaction list]                         │ ← unchanged (sole persistent feed)
│                                            │
├────────────────────────────────────────────┤
│ ┌────────────────────────────────────────┐ │
│ │ You: -500 b food                       │ │
│ │ AI:  Did you mean BPI or BDO?          │ │  ← dialog drawer
│ │ [BPI] [BDO]   [Cancel]                 │ │     transient — slides up when active,
│ └────────────────────────────────────────┘ │     slides away on resolve/cancel
├────────────────────────────────────────────┤
│ [📂] [✏️] [text field..............] [➤]   │  ← input row (replaces FAB column)
└────────────────────────────────────────────┘
```

- **Input row** (replaces FAB column):
  - 📂 → existing `ManageCategoriesSheet`
  - ✏️ → existing `AddTransactionSheet` (full form, no prefill)
  - Text field — natural-language input, also used to type clarification replies
  - Send button — spinner during AI turns
- **Dialog drawer** (only visible when `chatPhase != idle`):
  - Compact transcript: last 1–2 turns shown, scrollable if longer
  - Quick-reply chips when AI offers options (`[BPI] [BDO]`)
  - Always-visible Cancel button → drops conversation
  - Final resolving turn renders as `[Yes] [Edit] [Cancel]` row → Yes commits, Edit opens form prefilled, Cancel drops

### Outcomes

| State | Behavior |
|---|---|
| **Regex+dict fully resolves** | Commit immediately, snackbar `Logged ₱500 → Food (GCash)`. No AI call. No dialog. |
| **Hard error** (no amount, multiple amounts, too long, sign/category mismatch) | Error chip above input. Text preserved. No AI call. |
| **AI dialog needed** | Drawer slides up. AI asks clarifying questions in turns. User replies via text field or chips. Up to 3 clarifying turns; turn 4 forces fallback to form prefilled with everything gathered. |
| **AI's resolving turn** | Drawer shows summary + `[Yes] [Edit] [Cancel]`. Yes → commit + drop drawer. Edit → close drawer, open form prefilled. Cancel → close drawer, clear state. |
| **AI unavailable** (offline / model not downloaded / timeout) | Skip the dialog. If preprocessor result is minimally usable (has amount + account) → open form prefilled. Else → error chip. |

## 3. Parsing pipeline

Three layers; the first that resolves wins.

### 3.1 Preprocessor (regex+dict, sync, no I/O)

Same as before — see `lib/utils/finance_nlp_parser.dart`.

**Normalization:** lowercase, trim, strip currency symbols (`₱`, `php`, `p`+digits), strip thousand-commas (`1,500`→`1500`), normalize transfer aliases (`txfr|trf|t|>|->|→`→`transfer`).

**Patterns (priority order):**

| Pri | Pattern | Example |
|---|---|---|
| A | `transfer <amt> <accountA> [to] <accountB>` | `transfer 1000 bpi gcash` |
| B | `[+\|-]<amt> <token1> [...]` | `-500 food gcash` |
| C | `<amt> <token1> [...]` (unsigned) | `500 gcash hamburger` |

Per-token resolution order: account-exact → account-prefix(≥3) → account-fuzzy(Lev≤1, ≥4 chars) → category-exact → category-prefix → personal-dictionary lookup.

**Sign inference (no AI):** explicit `+`/`-` wins; else if exactly one resolved category whose `type` is unambiguous, infer outflow/inflow; else leave unsigned for AI.

**Output `PreparseResult`:**
```dart
class PreparseResult {
  final double? amount;
  final TransactionType? type;
  final String? accountId;
  final String? transferToAccountId;
  final String? categoryId;
  final List<String> unresolvedTokens;       // tokens that hit nothing
  final List<String> ambiguousAccountTokens; // tokens with ≥2 prefix matches
  final FinanceParseError? hardError;
}
```

**Hard errors short-circuit before AI:** empty, `>500` chars, no digits, multiple amounts, sign/category mismatch, no categories of needed type.

### 3.2 Personal dictionary

`lib/services/finance_personal_dictionary.dart`. Persists `token → categoryId` mappings learned from confirmed AI mappings. Cascade-cleared when a category is deleted. The preprocessor checks this before falling through to AI; the AI prompt also receives the dict so suggestions stay consistent.

### 3.3 AI dialog (multi-turn classifier)

Triggered only when preprocessor can't fully resolve and there's no hard error. Implemented via a **single AI service call per turn** that takes conversation history and returns one of three structured steps.

**Sealed `ClassifierStep`:**
```dart
sealed class ClassifierStep {}

class StepResolved extends ClassifierStep {
  final ParsedTransaction transaction;     // all fields filled, validated
  final String? learnedToken;              // token to write into personal dict on confirm
  final String summaryText;                // "Log ₱500 outflow → Food (GCash)?"
}

class StepClarify extends ClassifierStep {
  final String question;                   // free-form AI question
  final List<QuickReply>? quickReplies;    // optional chips
  final ParsedTransaction partialDraft;    // what's known so far (for Edit fallback)
}

class StepGiveUp extends ClassifierStep {
  final String reason;                     // shown to user as part of fallback hint
  final ParsedTransaction partialDraft;
}

class QuickReply {
  final String label;       // e.g. "BPI"
  final String replyText;   // text inserted as the user's reply
}
```

**Prompt (per turn, ~250 tokens, JSON-only, temp 0.1, 5s timeout):**

```
You are a finance transaction assistant. Output JSON only.

Existing accounts: ["BPI","GCash","BDO","Cash"]
Existing categories: [{"name":"Food","type":"expense"}, ...]
Learned token→category: {"hamburger":"Food","uber":"Transportation"}

Conversation:
  [t1 user] "-500 b food"
  [t1 ai]   {"step":"clarify","question":"Did you mean BPI or BDO?",
             "quickReplies":[{"label":"BPI","replyText":"BPI"},
                             {"label":"BDO","replyText":"BDO"}]}
  [t2 user] "BPI"

Preparser knowledge: {amount:500, type:outflow, account:null, category:"Food"}

Rules:
- Pick accounts ONLY from the existing list. Never invent.
- Pick categories ONLY from the existing list. Never invent.
- If a token is unknown, infer or ask — don't guess silently.
- If you have all required fields with confidence ≥ 0.8, return step:"resolved".
- If unsure, return step:"clarify" with one question and optional quickReplies.
- After 3 clarification turns total, return step:"give_up".

Required fields:
- inflow/outflow: amount, type, account, category, description
- transfer:       amount, account, transferTo, description (no category)

Output one of:
  {"step":"resolved","amount":500,"type":"outflow","account":"BPI",
   "transferTo":null,"category":"Food","learnedToken":null,
   "summaryText":"Log ₱500 outflow → Food (BPI)?"}
  {"step":"clarify","question":"...","quickReplies":[{"label":"...","replyText":"..."}]}
  {"step":"give_up","reason":"..."}
```

**Post-validation in code:**
- `account` and `transferTo` are looked up against the live account list; if AI returned a name not in the list → discard, force `give_up` to form fallback.
- `category` validated against list; if AI returned `expense` but type is `inflow` (or vice versa) → discard.
- Confidence < 0.6 (when present) → discard.
- Turn counter incremented; turn 4 forces `give_up` regardless of AI output.

**Response cache:** keyed on `sha1(conversation + accountListHash + categoryListHash + dictHash)`. Identical cycles are free (matters for repeated turn 1 inputs across sessions).

## 4. Edge cases

A central design promise: anything that previously failed should now turn into a question instead.

| Input | Old plan | Dialog plan |
|---|---|---|
| Empty / whitespace | No-op | No-op |
| `>500 chars` | Hard error | Hard error |
| No digits (`food gcash`) | Hard error | Hard error |
| `0` or negative magnitude | Reject | Reject |
| Multiple amounts (`-500 -300 food gcash`) | Reject | Reject (or AI asks "did you mean a transfer?" — see §6 prompt) |
| Decimals, commas, currency symbols | Normalized | Normalized |
| Sign/category mismatch (`+500 food gcash`) | Hard error | Hard error |
| `500 gcash food` (unsigned, category typed) | Sign inferred → commit | Sign inferred → commit |
| `500 gcash hamburger` | One-shot classify + confirm card | AI: `Log ₱500 outflow → Food (GCash)?` (one turn) |
| `-500 b food` (ambiguous account) | Form fallback | AI: `Did you mean BPI or BDO?` chips |
| `bought groceries` (vague, no amount) | Hard error | AI: `How much, and from which account?` — gathers in turns |
| `paid utang` (semantic, unknown intent) | Form fallback | AI: `Is this an expense, or a transfer to a creditor account?` |
| `transfer 1000 bpi` (missing target) | Form fallback | AI: `Transfer to which account?` chips |
| `1000 bpi gcash` (could be transfer or signed flow) | Form fallback (suggests transfer) | AI: `Transfer ₱1000 BPI → GCash?` |
| AI returns category not in list | Form fallback | Validator discards → AI re-asks (1 turn) → if still bad → give_up |
| AI returns invented account | Form fallback | Validator discards → give_up |
| AI confidence < 0.6 | Form fallback | Treat as `clarify` with a generic question |
| 3 clarifying turns reached without resolution | n/a | Drawer shows hint `Couldn't pin it down — opening the form…` and opens prefilled |
| User types non-answer in clarification turn | n/a | AI's next turn either re-asks more directly or `give_up` |
| User backgrounds app mid-conversation | n/a | State dropped on app pause/resume after >5 min, or on dispose |
| User taps Cancel | n/a | Drawer collapses, state cleared, input still has last typed text? **No** — input is also cleared (clean reset) |
| Past-date filter active | Input disabled | Input disabled, hint `View only — clear date filter to log` |
| Sub-account / inactive account token | Excluded | Excluded; AI prompt only sees active top-level accounts |

## 5. Data model changes

**Untouched:** TransactionRecord, FinanceCategory, FinancialAccount, transfer logic, balance updates.

**New (`lib/models/finance/finance_parse_result.dart`):**
```dart
class PreparseResult { ... }                  // §3.1
class ParsedTransaction { ... }               // accumulated draft
sealed class ClassifierStep { ... }           // §3.3 — Resolved / Clarify / GiveUp
class QuickReply { final String label, replyText; }

enum ChatPhase { idle, classifying, clarifying }

class LedgerChatTurn {
  final String text;
  final bool isUser;
  final List<QuickReply>? quickReplies;       // null for user turns
  final DateTime at;
}

class LedgerChatState {
  final ChatPhase phase;
  final List<LedgerChatTurn> turns;           // ephemeral, in-memory
  final ParsedTransaction draft;
  final int turnCount;                        // 0..3
  final ClassifierStep? lastStep;             // drives Yes/Edit/Cancel row when Resolved
}

enum FinanceParseError {
  empty, tooLong, noAmount, multipleAmounts, invalidAmount,
  signCategoryMismatch, noCategoriesForType, viewingPastDate,
}
```

`ParsedTransaction` is mergeable — each AI turn refines a partial draft, merging non-null fields onto the prior state.

## 6. AI service additions

`AiCoachService` gains:
```dart
Future<ClassifierStep?> runFinanceClassifierStep({
  required List<LedgerChatTurn> conversation,
  required PreparseResult preparse,
  required List<FinanceCategory> categories,
  required List<FinancialAccount> accounts,
  required Map<String, String> learnedMappings, // tokenLower → categoryId
  required int turnCount,
});
```

Implementations:
- `OnDeviceAiCoachService` — Qwen3 0.6B chat session, JSON-mode parser, 5s timeout, response cache. Mirrors structure of existing `disambiguateFood`.
- `CloudAiCoachService` — Bedrock Haiku call, same prompt.
- `NullAiCoachService` — returns null (forces fallback).

The prompt template encodes the rules from §3.3 verbatim. The response parser tolerates the model emitting prose around the JSON (extract first `{...}` block), and validates every named entity against the live lists.

## 7. Presenter changes

`lib/presenters/ledger_presenter.dart`:

```dart
final FinancePersonalDictionary _financeDict;
final AiCoachService _ai;

LedgerChatState _chatState = const LedgerChatState.idle();
String? _chatHardError;
String? _lastCommittedSummary;

LedgerChatState get chatState => _chatState;
String? get chatHardError => _chatHardError;
String? get lastCommittedSummary => _lastCommittedSummary;

Future<void> sendChatInput(String text) async {
  // If idle: kick off a new conversation.
  // If clarifying: append the user reply turn and run another AI step.
}

Future<void> confirmResolved() async {
  // Called by Yes button when lastStep is Resolved.
  // Commit transaction, write learnedToken to dict, snackbar, reset state.
}

void editResolved() {
  // Called by Edit button. Close drawer, open form with draft as prefill.
}

void cancelChat() {
  // Drop conversation, clear input. No commit, no learn.
}

void clearChatHardError() { ... }
```

State machine:

```
idle ──[user send]──▶ classifying ──[regex resolves]──▶ COMMIT ─▶ idle
                                  │
                                  └─[needs AI]─▶ AI step
                                                 ├─Resolved─▶ clarifying (Yes/Edit/Cancel row)
                                                 ├─Clarify──▶ clarifying (question + chips)
                                                 └─GiveUp───▶ open form prefilled, idle

clarifying ──[user reply / chip]──▶ classifying ──▶ AI step (turnCount++)
clarifying ──[Yes]────────────────▶ COMMIT, idle
clarifying ──[Edit]───────────────▶ open form prefilled, idle
clarifying ──[Cancel]─────────────▶ idle
```

App lifecycle: presenter listens to app lifecycle; on `paused` longer than 5 min (timer started on pause), reset chat state to idle.

`deleteCategory` cascades: remove dict entries pointing at the deleted id.

## 8. View changes

`lib/views/treasury/ledger/ledger_view.dart`:

1. **Remove** `floatingActionButton: Column(...)` block.
2. **Wrap** existing body Column children in `Expanded` so the bottom region docks below.
3. **Append** below the transaction list:
   - `_ChatHardErrorChip(presenter)` — visible only when `chatHardError != null`, dismissible.
   - `_LedgerChatDrawer(presenter)` — visible only when `chatState.phase != idle`. Animated `AnimatedSize` slide-in 200ms ease-out. Contains compact transcript + quick-reply chips (when AI's last step is `Clarify`) or `[Yes] [Edit] [Cancel]` row (when last step is `Resolved`) + always-visible small Cancel.
   - `_LedgerChatInputBar(presenter, onOpenForm: ..., onOpenCategories: ...)`.
4. **`_LedgerChatInputBar`** modeled on `_ChatInputBar` (`nutrition_screen.dart` lines 1515–1643):
   - 📂 IconButton → `ManageCategoriesSheet`
   - ✏️ IconButton → `AddTransactionSheet` (no prefill)
   - Rounded `surfaceContainerHigh` `TextField`, hint adapts (`Log a transaction…` / `Reply…` / `Fasting — view only` / etc.)
   - Send button: arrow icon, swaps to `CircularProgressIndicator(strokeWidth: 2)` while `phase == classifying`
5. **`_LedgerChatDrawer`** layout:
   ```dart
   AnimatedSize(
     duration: 200ms,
     child: phase == idle ? SizedBox.shrink() : Container(
       padding: 12,
       color: cs.surfaceContainerLow,
       child: Column(
         children: [
           _Transcript(turns: state.turns.takeLast(3)),
           if (state.lastStep is StepClarify) _QuickReplyRow(replies),
           if (state.lastStep is StepResolved) _ResolveActions(onYes, onEdit, onCancel),
           if (state.lastStep is StepClarify) Align(alignment: bottomRight,
             child: TextButton(onPressed: presenter.cancelChat, child: 'Cancel')),
         ],
       ),
     ),
   );
   ```
6. **Send handler** routes to `presenter.sendChatInput(text)` regardless of phase. The presenter decides whether it's a new conversation or a reply.
7. **Theme-aware colors only** (CLAUDE.md rule 7 + dual-theme memory).

## 9. Tests

### `test/utils/finance_nlp_parser_test.dart` (preprocessor only)
Same coverage as previous plan: happy paths, sign inference, currency normalization, fuzzy matching, ambiguity detection, hard errors, dict hits.

### `test/services/finance_personal_dictionary_test.dart`
learn / lookup / remove round-trip; cascade-clear on category delete; persistence via mock storage.

### `test/presenters/ledger_presenter_test.dart` (extend)
Use a `FakeAiCoachService` that replays a scripted sequence of `ClassifierStep`s.

- Regex fully resolves → commit, no AI call.
- Dict hit → commit, no AI call.
- AI returns `Resolved` turn 1 → state moves to `clarifying` with Resolved, **no commit yet**.
- `confirmResolved` → commit + dict.learn(learnedToken).
- AI returns `Clarify` → state shows question + chips; `sendChatInput(reply)` advances turn.
- AI returns `Clarify` 3 times → 4th step forced to `GiveUp` → form fallback path triggered.
- AI returns category not in list → discarded by validator → step retried as `Clarify` (or `GiveUp`).
- AI returns invented account → `GiveUp`.
- `cancelChat` → state cleared, no commit, no learn.
- App backgrounded for >5 min → state reset.
- Hard error (no amount) → no AI call, error chip set.

### `test/services/on_device_ai_coach_service_test.dart` (extend)
- `runFinanceClassifierStep` JSON parsing happy path for each step type.
- Malformed JSON → returns null.
- Hallucinated entity → caller-side validator catches, but service-side parsing succeeds.
- Cache hit returns instantly without invoking the model.

## 10. File map

**New:**
- `lib/utils/finance_nlp_parser.dart` (~280 lines)
- `lib/models/finance/finance_parse_result.dart` (~180 lines — preparse, draft, ClassifierStep sealed types, chat state)
- `lib/services/finance_personal_dictionary.dart` (~80 lines)
- `test/utils/finance_nlp_parser_test.dart` (~250 lines)
- `test/services/finance_personal_dictionary_test.dart` (~80 lines)

**Modified:**
- `lib/services/ai_coach_service.dart` — add `runFinanceClassifierStep` to abstract.
- `lib/services/on_device_ai_coach_service.dart` — implement classifier step (Qwen prompt + JSON parse + cache + validator).
- `lib/services/cloud_ai_coach_service.dart` — implement classifier step.
- `lib/services/null_ai_coach_service.dart` — return null.
- `lib/services/storage_service.dart` + `local_storage_service.dart` — `loadFinanceDictionary` / `saveFinanceDictionary`.
- `lib/presenters/ledger_presenter.dart` — chat state machine, lifecycle hook, dict cascade.
- `lib/views/treasury/ledger/ledger_view.dart` — remove FAB column, add `_LedgerChatDrawer`, `_LedgerChatInputBar`, `_ChatHardErrorChip`.
- `lib/views/treasury/ledger/add_transaction_sheet.dart` — optional `ParsedTransaction? prefill` arg.
- `test/presenters/ledger_presenter_test.dart` — chat state-machine cases.
- `test/services/on_device_ai_coach_service_test.dart` — classifier-step tests.

**Untouched:** TransactionRecord, FinanceCategory, FinancialAccount, ledger CRUD, transfer logic, summary cards, account filter row.

## 11. Implementation order

Each chunk mergeable on its own.

1. **Models + preprocessor + dict + tests** — pure logic, no UI, no AI. Heavy unit-test coverage. The fast-path is fully usable from the form even before chat ships.
2. **AI classifier step** — extend `AiCoachService` interface + on-device + cloud + null impls + tests. The classifier is unused in the app at this point; tested in isolation.
3. **Presenter wire-up** — `sendChatInput`, state machine, lifecycle hook, snackbar summary, dict cascade. Presenter tests with `FakeAiCoachService`.
4. **View** — replace FAB with chat input row; build `_LedgerChatDrawer` with transcript, quick-reply chips, Yes/Edit/Cancel row, animated slide-in. Wire `Edit` to open `AddTransactionSheet` with prefill.
5. **Polish** — empty-state hints, accessibility (44×44 touch targets per CLAUDE.md rule 4), animations 150–300ms (CLAUDE.md rule 5), snackbar style, ensure `dart format` runs cleanly before each commit.

## 12. Risks & mitigations

- **AI dialog loops** — bounded by `turnCount`; 4th step is forced `GiveUp`. Tests guard this.
- **AI returns invented entities** — every named field validated against the live list; invalid ones force re-clarify or give_up. Account is double-validated (preprocessor and AI both restricted).
- **Latency per turn (~3–5s)** — only paid when needed (regex fast-path skips AI). Send button shows spinner. Cache makes repeated queries free.
- **Conversation state lost on background** — intentional; ledger entries should be deliberate, not resumed half-typed an hour later. 5-min lifecycle guard handles momentary backgrounds.
- **AI cost (cloud tier)** — Bedrock Haiku ~$0.0001/turn; rare (only triggered on ambiguous inputs); cache further dampens.
- **Dict pollution** — only confirmed mappings learn; cascade-cleared with category deletes; out-of-scope review UI tracked for v2.
- **Description truncation at 60** — raw input captured up to 60 chars; note stays null on chat-logged entries.
- **Theme-aware colors only** (CLAUDE.md rule 7 + dual-theme memory).

## 13. Out of scope (v1)

- Multi-transaction in one message (`-500 food gcash, -200 transport gcash`).
- Date prefixes (`yesterday -500 food gcash`).
- AI auto-creating categories or accounts.
- Voice input.
- Editing past transactions via chat.
- Dict review/edit UI.
- Recurring transactions via chat.
- Persisting in-flight conversations across app restarts.

## 14. Tweakable defaults (call out to revisit)

- **Max clarification turns: 3** (turn 4 forces give_up). Raise if AI is good at converging; lower if turns feel like grinding.
- **Background-reset threshold: 5 min**. Lower for stricter "deliberate entry" UX; raise to be more forgiving of brief context switches.
- **AI confidence cutoff: 0.6**. Below this, treat any `Resolved` step as `Clarify`.
- **Description = raw input truncated at 60**. Could instead extract just the trailing free-form words.
- **AI runs only when regex+dict can't fully resolve.** Flip to "always" if you ever want AI as a sanity check on simple inputs.
