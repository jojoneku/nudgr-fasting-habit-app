# Chat Logging Coverage

What the chat/quick-log parser can and cannot set, measured field by field
against the manual ledger form (`lib/views/treasury/ledger/add_transaction_sheet.dart`).

Read this before sending a user to chat for something, or before assuming chat
is a full replacement for the form. It is not — and two of the gaps are silent.

**Pipeline:** regex + dictionary preparse (`lib/utils/finance_nlp_parser.dart`)
→ AI classifier, cloud then on-device (`lib/utils/finance_classifier_parser.dart`)
→ prefilled form. Each layer only handles what the one before it couldn't.

---

## 1. Field-by-field

Every field the form writes onto a `TransactionRecord`, and whether chat can
reach it.

| Field | Manual form | Chat | Gap |
|---|---|---|---|
| **type** | 3-way toggle | Sign (`-500`/`+5000`), category type, transfer keywords | — |
| **amount** | Calculator field: `285+15`, `× ÷` | Plain number only | Chat has no arithmetic |
| **account** | Dropdown, all active non-sub | Exact / prefix / fuzzy / multi-word span; sole-account fallback | Chat excludes custodians |
| **transferTo** | Dropdown | `to` / `into` / `from` markers, else word order | — |
| **category** | Picker sheet | Name, prefix, learned dictionary (typo-tolerant), AI inference | — |
| **description** | Free text, uncapped | Derived from raw input, extraction tokens stripped, **capped at 60 chars** | Silent truncation |
| **note** | Free text | **Cannot set** | Chat-blind field |
| **date** | Date picker, any date | **Always today** | Cannot back-date |
| **reimbursable** | Switch | Auto-detected from phrasing | — |
| **expectedReimbursementDate** | Date picker | **Always null ("ASAP")** | Chat-blind field |
| **owedBy** | Free text | **Cannot set** | Chat-blind field |

`billId`, `receivableId` and `installmentId` are set by neither surface — they
are written by the Bills and Installments pages.

### The two silent gaps

Everything above is either visible or harmless except these, which produce a
committed transaction that quietly differs from what the form would have made:

1. **Description over 60 characters is truncated** without a word to the user
   (`_truncateDescription`, `ledger_presenter.dart`). A long chat entry loses
   its tail.
2. **A reimbursable logged from chat is always "ASAP"** with no `owedBy`. The
   linked receivable lands in the current month and names nobody, so
   "spotted Jana 800, she'll pay me back" tracks the money but not who owes it.

---

## 2. Chat can do things the form cannot

| Capability | What it does | Where |
|---|---|---|
| **Several entries per message** | `-500 food gcash and -300 grab bpi` → two transactions, one confirm | `preparseFinanceBatch` |
| **Credit-card pay-down** | `paid bpi cc 5000 from gcash` → transfer that pays the card down, not an expense | `_tryPayCredit` |
| **Spotted-for-someone wash** | `paid 800 on my cc for jana, she paid me back` → card→cash transfer, neither spending nor income | `_tryPaidForSomeone` |
| **Reimbursable detection** | "work expense", "owes me", "will pay me back" pre-arms the toggle | `_detectReimbursable` |
| **Learned categories** | Confirmed token→category mappings resolve later entries with no AI call; survives one typo | `FinancePersonalDictionary`, `_lookupLearned` |
| **Receipt photo** | Merchant + total seed the same confirm pipeline | `logReceiptPhoto` |
| **Currency noise** | `₱120`, `php120`, `120 pesos`, `1,500` all normalize | `_normalize` |

The form has a "Paid for someone" preset button for the third case, so that one
is a shortcut rather than an exclusive.

## 3. The form can do things chat cannot

- **Edit or delete.** Chat only ever creates. Every correction is a form trip.
- **Back-date.** Chat stamps `DateTime.now()`, and refuses outright while you
  are browsing a past date (`viewingPastDate`).
- **Custodian accounts.** The form offers them; chat's account pool excludes
  them by design (Plan 026 §4).
- **Convert between kinds.** Transfer ↔ expense/income re-typing is form-only.
- **Note, owedBy, expected payback date, amount arithmetic** — see §1.

Neither surface reaches **sub-accounts** (savings pockets). Both filter them out.

---

## 4. Hard limits

| Limit | Value | Behaviour past it |
|---|---|---|
| Message length | 500 chars | `tooLong` error, no AI call |
| Segments per message | 10 | Parsed as one entry instead of a list |
| Amounts per segment | 1 | `multipleAmounts` error — `-500 -300 food gcash` is rejected |
| Clarify turns | 3 | Gives up, opens the prefilled form |
| Account prefix match | ≥3 chars | Below that: ambiguous, not resolved |
| Account fuzzy match | ≥4 chars, edit distance ≤1, unique | Ties are ambiguous, not a guess |
| Account name width | 4 words | A 5-word account name is never matched whole |
| Confidence floor | 0.6 | Below: downgraded to a clarifying question |

### Segmentation rules

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

## 5. Ambiguity: what gets asked vs assumed

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

---

## 6. Known asymmetries worth a decision

Not bugs today, but each is a place chat and the form disagree:

1. **Description truncation is silent.** Either warn at 60 chars or raise the
   cap to match the form.
2. **Reimbursables lose `owedBy`.** The phrasing usually contains the name
   ("spotted **Jana** 800") — the classifier could extract it.
3. **Back-dating is impossible.** "yesterday" / "last friday" is common
   phrasing the parser does not read.
4. **No amount arithmetic.** The form's calculator field accepts `285+15`;
   chat rejects it as two amounts.
