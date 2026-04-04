# Plan 012 — AI Transaction Chat
**Status:** DRAFT v2 — Awaiting Approval
**Phase:** 1 of 1
**Depends on:** Plans 004a–004c (Treasury module) — completed

---

## Goal

A chat screen where the user types any natural language transaction description. The AI classifies the **intent**, extracts structured fields, and either shows a confirmation card or asks a clarifying question — never silently mis-parses.

Runs 100% on-device via the existing `flutter_gemma` / Gemma 3 1B setup. No new dependencies.

---

## Intent Classification

The AI is responsible for understanding intent — the app never assumes a word order or pattern.

| Intent | Example inputs |
|---|---|
| `log_outflow` | `"200 food gcash"`, `"gcash food 200"`, `"spent 150 on grab"`, `"500 groceries bpi"` |
| `log_inflow` | `"received salary 51k bpi"`, `"got 5000 from client maya"`, `"bpi salary 51000 received"` |
| `log_transfer` | `"transfer 5000 gcash to bpi"`, `"moved 2k from bpi to maya"` |
| `log_multiple` | `"200 food gcash, 150 grab transport"`, `"food 200 and transport 150 both gcash"` |
| `undo_last` | `"undo"`, `"cancel that"`, `"remove last"`, `"nevermind"` |
| `unknown` | anything unclear, ambiguous, or non-transaction → AI responds with a clarifying question |

If the AI cannot confidently resolve **any field** (amount, account, category, type), it sets `intent: unknown` and returns a `clarificationMessage` explaining what it needs. It never guesses silently.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/finance/ai_transaction_parse_result.dart` | Create | Model |
| `lib/models/chat_message.dart` | Create | Model |
| `lib/services/ai_estimation_service.dart` | Modify | Service |
| `lib/presenters/transaction_chat_presenter.dart` | Create | Presenter |
| `lib/views/treasury/ledger/transaction_chat_view.dart` | Create | View |
| `lib/views/treasury/ledger/ledger_view.dart` | Modify | View |
| `lib/views/home_screen.dart` | Modify | Wiring |

---

## Interface Definitions

### `AiTransactionParseResult` (ephemeral — never persisted)

```dart
enum ChatIntent {
  logOutflow,
  logInflow,
  logTransfer,
  logMultiple,
  undoLast,
  unknown,
}

class ParsedTransaction {
  final double amount;
  final TransactionType type;       // inflow | outflow
  final String? accountId;          // null if unresolved
  final String? toAccountId;        // transfer destination only
  final String? categoryId;         // null if unresolved
  final String description;
}

class AiTransactionParseResult {
  final ChatIntent intent;
  final List<ParsedTransaction> transactions; // empty for undo_last / unknown
  final String? clarificationMessage;         // non-null when intent == unknown
}
```

### `ChatMessage` (ephemeral — session only, never persisted)

```dart
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
}
```

### `AiEstimationService` — new method

```dart
Future<AiTransactionParseResult> parseTransaction(
  String input,
  List<FinancialAccount> accounts,
  List<FinanceCategory> categories,
);
```

**System prompt** — injected with real account and category data:

```
You are a transaction parser for a personal finance app.
The user will describe one or more financial transactions in natural language.
Any word order is valid — do not assume a fixed format.

Available accounts (use exact IDs):
[{"id":"a1","name":"GCash"},{"id":"a2","name":"BPI"},...]

Available categories (use exact IDs):
[{"id":"c1","name":"Food & Drinks","type":"expense"},
 {"id":"c2","name":"Transport","type":"expense"},
 {"id":"c3","name":"Salary","type":"income"},...]

Classify the intent and extract fields. Respond with ONLY valid JSON — no markdown, no explanation:

{
  "intent": "log_outflow|log_inflow|log_transfer|log_multiple|undo_last|unknown",
  "transactions": [
    {
      "amount": number,
      "type": "inflow|outflow",
      "accountId": "string|null",
      "toAccountId": "string|null",
      "categoryId": "string|null",
      "description": "string"
    }
  ],
  "clarificationMessage": "string|null"
}

Rules:
- If ANY required field is ambiguous or missing, set intent to "unknown" and
  set clarificationMessage to a short, friendly question asking only what's missing.
- For log_multiple, include one entry per transaction in the transactions array.
- For log_transfer, set type="outflow", accountId=source, toAccountId=destination.
- For undo_last and unknown, transactions must be an empty array [].
- Never guess an account or category if unsure — ask instead.
- amounts like "1k" = 1000, "5.5k" = 5500, "51k" = 51000.
```

### `TransactionChatPresenter`

```dart
class TransactionChatPresenter extends ChangeNotifier {
  TransactionChatPresenter(AiEstimationService ai, LedgerPresenter ledger);

  List<ChatMessage> get messages;
  AiTransactionParseResult? get pendingResult; // non-null → confirmation card visible
  bool get isThinking;
  bool get isModelAvailable;

  Future<void> sendMessage(String text);
  // - Appends user message
  // - Sets isThinking = true
  // - Calls ai.parseTransaction(text, accounts, categories)
  // - If intent == unknown: appends clarificationMessage as AI bubble, clears pending
  // - If intent == undo_last: calls _undoLast(), appends confirmation message
  // - Else: sets pendingResult, appends "Got it! Confirming:" AI bubble

  Future<void> confirmTransaction();
  // - For each ParsedTransaction in pendingResult.transactions:
  //     if transfer → ledger.addTransfer(...)
  //     else → ledger.addTransaction(...)
  // - Appends success message (e.g. "✓ Logged ₱200 outflow from GCash")
  // - Clears pendingResult

  void rejectTransaction();
  // - Clears pendingResult
  // - Appends AI message: "No problem. What would you like to log?"

  void clear(); // reset session
}
```

---

## Implementation Order

1. [ ] Create `ParsedTransaction`, `AiTransactionParseResult`, `ChatMessage` models
2. [ ] Add `parseTransaction()` to `AiEstimationService` with intent-based system prompt
3. [ ] Create `TransactionChatPresenter`
4. [ ] Wire into `AppShell` (inject existing `_ai` + `_ledgerPresenter`)
5. [ ] Build `TransactionChatView`
6. [ ] Add chat entry point to `LedgerView`

---

## View Spec — `TransactionChatView`

```
┌─────────────────────────────────────────────────┐
│  ← AI TRANSACTION LOG                           │
│─────────────────────────────────────────────────│
│                                                 │
│              gcash food 200              👤     │
│                                                 │
│  🤖  Got it! Confirming:                        │
│  ┌─────────────────────────────────────────┐    │
│  │  ▼ ₱200.00 outflow                      │    │
│  │  Account:   GCash                       │    │
│  │  Category:  Food & Drinks               │    │
│  │  Date:      Today                       │    │
│  │                                         │    │
│  │   [  ✓ Confirm  ]    [  ✗ Cancel  ]     │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  transfer 5000 bpi to gcash              👤     │
│                                                 │
│  🤖  I see 2 accounts but I'm not sure which   │
│      is the source. Is it BPI → GCash or       │
│      GCash → BPI?                              │
│                                                 │
│─────────────────────────────────────────────────│
│  [Type a transaction...           ]  [Send ➤]  │
└─────────────────────────────────────────────────┘
```

- User bubbles: right-aligned, accent color border
- AI bubbles: left-aligned, surface color
- Confirmation card: shown inside AI bubble area; one card per parsed transaction if `log_multiple`
- "Thinking..." animated dots while `isThinking`
- `!isModelAvailable`: banner at top — "AI model not installed" + Download button (same CTA as Alchemy Lab)
- Clarification message: plain AI bubble, no confirmation card — user just replies

---

## RPG Impact

No new XP rules. `LedgerPresenter.addTransaction()` already awards:
- **+25 XP** on first-ever transaction
- **+10 XP** on first transaction of the day

All chat transactions flow through the same method — rewards apply automatically.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Gemma mis-matches account ("maya" hits "Maya Savings" not "Maya Wallet") | Multiple partial matches → `intent: unknown` + clarification question |
| Model not downloaded | Download CTA banner — same UX as Alchemy Lab |
| No accounts or categories set up yet | Show inline prompt: "Add accounts and categories in the Ledger first" |
| JSON parse failure from model | Catch `FormatException` → append `"Sorry, something went wrong. Try rephrasing."` |
| `log_multiple` partial failure (1 of 3 fails) | Commit all that succeed, report which failed in AI message |
| `undo_last` when no transactions exist | AI message: "Nothing to undo yet." |

---

## Acceptance Criteria

- [ ] `"200 food gcash"` and `"gcash food 200"` and `"food gcash 200"` all produce the same confirmation
- [ ] `"received salary 51k bpi"` → inflow confirmation ₱51,000 / BPI / Salary
- [ ] `"transfer 5000 gcash to bpi"` → transfer confirmation, both balances update on confirm
- [ ] `"200 food gcash, 150 grab"` → 2 confirmation cards shown together
- [ ] `"undo"` → last transaction deleted, AI confirms what was removed
- [ ] Ambiguous input → AI asks a clarifying question, never silently mis-parses
- [ ] Model unavailable → download CTA shown, no crash
- [ ] JSON parse failure → friendly error message in chat
- [ ] All touch targets ≥ 44×44px
- [ ] No logic in `build()` — all state via presenter getters

---

*Present this plan for approval before writing any code. Proceed to `/feature 012` after approval.*
