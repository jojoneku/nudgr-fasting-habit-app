# Chat Logging Coverage

What the chat/quick-log parser can and cannot set, measured field by field
against the manual ledger form (`lib/views/treasury/ledger/add_transaction_sheet.dart`).

Read this before sending a user to chat for something, or before assuming chat
is a full replacement for the form.

**Pipeline (Plan 058):** the whole message goes to the cloud extractor in ONE
call (`lib/utils/finance_entry_extraction.dart`), which returns every
transaction in it as an array; names are bound against the live account and
category lists, and any field it couldn't determine is marked `missing` and
resolved with a picker on the confirm card
(`lib/views/widgets/finance/entry_review_card.dart`).

The regex + dictionary preparse (`lib/utils/finance_nlp_parser.dart`) and the
per-fragment AI classifier (`lib/utils/finance_classifier_parser.dart`) are the
**fallback**, reached only when the extractor has no transport (offline, over
the daily cap) or returns something unparseable. They are no longer allowed to
split the message before the model reads it: that is what dropped context
stated once across a list, and it is why "add in maribank 175 and 90 for
personal shopping. then 115 for food and drinks avocado ice cream all
yesterday" lost the ice cream's description and dated nothing.

---

## 1. Field-by-field

Every field the form writes onto a `TransactionRecord`, and whether chat can
reach it.

| Field | Manual form | Chat |
|---|---|---|
| **type** | 3-way toggle | Sign (`-500`/`+5000`), category type, transfer keywords |
| **amount** | Calculator field: `285+15`, `× ÷` | Same expressions, evaluated by the same `evalAmountExpression` |
| **account** | Dropdown, all active non-sub | Exact / prefix / fuzzy / multi-word span; sole-account fallback |
| **transferTo** | Dropdown | `to` / `into` / `from` markers, else word order |
| **category** | Picker sheet | Name, prefix, learned dictionary (typo-tolerant), AI inference |
| **description** | Free text, uncapped | Derived from raw input, metadata stripped, capped at 120 with an ellipsis |
| **note** | Free text | `note: …` or `// …` to end of segment |
| **date** | Date picker, any date | Resolved to an absolute date by the model against today; a date chip on the card edits it. The fallback path still uses the phrase table in §4 |
| **reimbursable** | Switch | Auto-detected from phrasing |
| **expectedReimbursementDate** | Date picker | A date behind a payback cue ("pays me back friday") |
| **owedBy** | Free text | Extracted from lend/payback phrasing, or supplied by the AI |

`billId`, `receivableId` and `installmentId` are set by neither surface — they
are written by the Bills and Installments pages.

Field parity is now complete except **custodian accounts** (§3) and the
operations chat structurally cannot perform: **edit and delete**.

**A second create path exists (Nudgy's `addTransaction` tool).** It is not a
replacement for this one and is deliberately weaker: one entry per call, no
context-stated-once, no learned dictionary, no receipt photos, and it refuses
rather than guessing when the account or category does not resolve. It exists
for entries that only became clear through the conversation — settling a bill
the advisor just looked up, an amount worked out together — which never reach
the pipeline above because the intercept in `AiCoachPresenter.send` only fires
on text that already reads as a log. Anything a user simply types to be logged
should go through this pipeline, not that tool.

---

## 2. Chat can do things the form cannot

| Capability | What it does | Where |
|---|---|---|
| **Several entries per message** | `-500 food gcash and -300 grab bpi` → two transactions, one confirm | the extractor's array; `preparseFinanceBatch` on the fallback path |
| **Context stated once** | `in maribank … all yesterday` sets the account and date for every entry in the message | extractor prompt rule 2 — the fallback path cannot do this |
| **Fill a gap without retyping** | A row missing an account gets a dropdown on the card, not a question and another round trip | `EntryReviewCard`, `LedgerPresenter.setEntry*` |
| **Credit-card pay-down** | `paid bpi cc 5000 from gcash` → transfer that pays the card down, not an expense | `_tryPayCredit` |
| **Spotted-for-someone wash** | `paid 800 on my cc for jana, she paid me back` → card→cash transfer, neither spending nor income | `_tryPaidForSomeone` |
| **Reimbursable detection** | "work expense", "owes me", "pays me back" arms the toggle and pulls out the debtor | `_detectReimbursable`, `_extractExtras` |
| **Learned categories** | Confirmed token→category mappings resolve later entries with no AI call; survives one typo | `FinancePersonalDictionary`, `_lookupLearned` |
| **Receipt photo** | Merchant + total seed the same confirm pipeline | `logReceiptPhoto` |
| **Currency noise** | `₱120`, `php120`, `120 pesos`, `1,500` all normalize | `_normalize` |

The form has a "Paid for someone" preset button for the third case, so that one
is a shortcut rather than an exclusive.

## 3. The form can do things chat cannot

- **Edit or delete.** Chat only ever creates. Every correction is a form trip.
  This was called structural on the grounds that a chat line names no existing
  row. That reasoning no longer holds: Nudgy's tool loop reads rows with their
  ids before it writes, which is exactly how it edits bills and set-asides. It
  is a gap that has not been closed yet, not one that cannot be. Closing it
  needs a correction-intent carve-out in the intercept first, or a phrase like
  "change the coffee to 150" gets swallowed here and logged as a second entry
  before any edit tool sees it.
- **Custodian accounts.** The form offers them; chat's account pool excludes
  them, and deliberately so. Custodian accounts are usually named after people
  ("Jana's money"), and chat text mentions people constantly — putting them in
  the fuzzy-matching pool would make `spotted jana 800` resolve *jana* to an
  account instead of a debtor. Use the form for money you hold for someone.
- **Reach sub-accounts** (savings pockets) — excluded from both surfaces.

---

## 4. Dates

| Phrase | Result |
|---|---|
| *(none)* | Now, as before |
| `today` | Today |
| `yesterday` | −1 day |
| `day before yesterday` | −2 days |
| `5 days ago` | −5 days |
| `last week` | −7 days |
| `friday` | The most recent Friday (today, if today is Friday) |
| `last friday` | The Friday before that — a full week back when today is Friday |
| `august 3`, `3 august`, `aug 3` | That day this year, or last year if it would be in the future |
| `2026-07-04` | That day |

A back-dated entry is stamped at midday, keeping it clear of both day boundaries
whatever the reader's timezone; an entry dated today keeps the real clock time so
same-day ordering still reflects when you logged. The ledger snaps to the
entry's month, not the current one, so `yesterday` on the 1st is visible where it
actually landed.

Deliberately **not** read as dates, because a false positive silently moves
money to the wrong month:

- **Three-letter weekday abbreviations** (`sun`, `mar`) — they collide with real
  account names. Weekdays must be spelled in full.
- **A month abbreviation that prefix-matches an account name** — `mari 20` stays
  Maribank, not 20 March.
- **Slash forms** (`08/20`) — indistinguishable from the division the calculator
  syntax allows.
- **An impossible day** (`february 31`) — treated as not-a-date rather than
  rolled into March.

A date phrase is consumed before amount extraction, so the digits in
`3 days ago` can never be read as a second amount.

## 5. Who owes it back

`owedBy` comes from, in order: `spotted|lent|loaned|fronted|sponsored <name>`,
`<name> owes me`, `owed by <name>`, then `for <name>` — that last one **only**
when the text also says the money is coming back, so `for lunch` never names
lunch as the debtor. Account names and a stop-list of common non-names are
rejected as candidates. Casing is read back from the raw input, so "Jana" stays
"Jana". If the preparser finds nothing, the AI may supply one; it is instructed
never to guess when no person is named.

Both `owedBy` and the payback date are dropped unless the entry is actually
reimbursable — a debtor on money nobody owes is worse than no debtor.

A date is the **payback** date only when it follows a payback cue; otherwise it
is the transaction date. `spotted Jana 800 yesterday, she pays me back monday`
sets both, correctly and separately.

---

## 6. Hard limits

| Limit | Value | Behaviour past it |
|---|---|---|
| Message length | 500 chars | `tooLong` error, no AI call |
| Segments per message | 10 | Parsed as one entry instead of a list |
| Amounts per segment | 1 | `multipleAmounts` error — `-500 -300 food gcash` is rejected |
| Description | 120 chars | Cut on a word boundary, marked with `…` |
| Clarify turns | 3 | Gives up, opens the prefilled form |
| Account prefix match | ≥3 chars | Below that: ambiguous, not resolved |
| Account fuzzy match | ≥4 chars, edit distance ≤1, unique | Ties are ambiguous, not a guess |
| Account name width | 4 words | A 5-word account name is never matched whole |
| Confidence floor | 0.6 | Below: downgraded to a clarifying question |

### Arithmetic

`285+15`, `150*3`, `1500/3`, `150×2`, `900÷3` all evaluate, with normal
precedence. The operator must carry **no surrounding whitespace** — that is
what keeps `-500 -300` two ambiguous amounts rather than silently becoming 200.
So `285 + 15` is *not* read as arithmetic; it is two amounts, and rejected.

### Segmentation

A message splits on newline, `;`, `,`, and ` and / then / also / plus ` — but
**only if at least two pieces carry a digit.** That guard is what keeps prose
intact:

- `coffee and donuts 150 gcash` → one entry, description survives
- `paid 800 on my cc for jana, she paid me back` → one entry, wash transfer
- `1,500 food gcash` → one entry (thousand-commas collapse before splitting)
- `-500 food gcash and -300 grab bpi` → two entries

Pieces without a digit are dropped as noise, so a leading `logged:` or a
trailing `and that's it` costs nothing.

### Batch outcomes

Segments are handled independently, then reported together:

- **All resolved by the parser** → committed immediately, no AI call, one toast.
- **Some need the AI** → one classifier call per unresolved segment, run
  concurrently, then a single confirm card listing every entry. Nothing commits
  until you confirm.
- **A segment the AI can't pin down** → carried on the card as "N more need a
  detail", and asked about one at a time *after* the confirmed ones are logged.
- **A malformed segment** (two amounts, contradictory sign) → cannot be fixed by
  asking, so it is reported as "N entries I couldn't read — retype those" and
  never enters the clarify queue.

Cancel drops the whole message, queued leftovers included.

---

## 7. Ambiguity: what gets asked vs assumed

Chat resolves without asking when:

- The account name is unambiguous, **including multi-word names** — "bpi
  personal" resolves rather than asking which BPI.
- There is exactly one loggable account (naming it is then optional).
- The category is named, learned, or a near-certain inference.

Chat asks when:

- A bare shared prefix is genuinely ambiguous — `bpi` across BPI Personal /
  Vybe / CC.
- Two learned tokens sit equally near a typo.
- A transfer's second leg is missing.

Chat never guesses:

- The account, when several are plausible. There is no most-recently-used
  fallback, deliberately — a wrong account is a wrong balance on two accounts.
- A category whose type contradicts the sign (`+500` with an expense category is
  a hard error, not a correction).
- A date, from anything on the not-read list in §4.
- A debtor, on an entry that isn't reimbursable.

## 8. One rule worth remembering

**The preparser's findings are never overwritten by the model.** A resolved
classifier step is *merged* onto the existing draft, not substituted for it, and
the fields the preparser derives deterministically — the reimbursable flag, the
dates, the note, the debtor — are not things the model is asked to restate.
Rebuilding the draft from the response alone is what used to drop them.

The one exception is `owedBy`, which the model may supply when the preparser
found none.
