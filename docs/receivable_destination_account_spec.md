# Receivable Destination Account Spec

> Status: **implemented** · Owner: System Architect

## Overview

A bill lets you choose which account is debited **at the moment you mark it
paid** — web shows a "Pay from" dropdown in the confirm dialog. A receivable
does not offer the mirror of that on web: the destination is computed silently
and shown as read-only prose ("into BPI Savings"), with no way to redirect it.

This gives receivables the same settle-time control bills already have, and
fixes the eligible-account rule, which is currently wrong in opposite
directions on each platform.

## User Story

As a user marking a reimbursement received, I want to pick which account the
money lands in — the same way I pick which account a bill is paid from — so
that a deposit that didn't go to my default account is recorded where it
actually went.

## Current Behaviour

| | Bills (settle) | Receivables (settle) |
|---|---|---|
| Mobile | account picker | account picker |
| Web | "Pay from" dropdown | **read-only text** |

Both *add* forms already store a default `accountId`; `Receivable.accountId`
exists and is documented as "optional default destination account". Nothing in
the model or presenter needs to change to hold the value — this is a settle-time
UI gap plus an eligibility bug.

### The eligibility bug

The set of accounts offered as a receivable destination differs per platform,
and neither is right:

- **Web** (`web_bills_page.dart` `_markReceived`) falls back to
  `isActive && isLiquid`. `isLiquid` is only bank / ewallet / cash
  (`financial_account.dart:96`), so **savings, goal, time-deposit and
  investment accounts are unreachable** — depositing a salary into savings is
  ordinary and currently impossible to record on web.
- **Mobile** (`bills_receivables_view.dart` `_MarkReceivedSheetState`) offers
  `presenter.accounts` — everything, including **archived accounts and
  liabilities**.

Receiving into a liability is incoherent here: `markReceivableReceived` posts a
plain **inflow** via `_buildInflowTxn`, so crediting a credit card would record
income against the card rather than paying it down.

Correct set: **active, non-liability** accounts — every asset pocket you can
actually deposit into, and nothing you can't.

## Data Model

No change. `Receivable.accountId` already exists and is already read and written
by both add-forms.

## Presenter API

One addition, mirroring the existing `payerAccountsFor`:

```dart
class BillsReceivablesPresenter {
  /// Accounts eligible to receive [receivable]'s money: active and
  /// non-liability. Mirrors [payerAccountsFor] for the inflow direction.
  /// [receivable] is accepted for symmetry and future per-record rules; the
  /// current rule does not depend on it.
  List<FinancialAccount> depositAccountsFor(Receivable? receivable);

  /// The account to preselect: the receivable's saved default when still
  /// eligible, else the first liquid account, else the first eligible one.
  /// Keeps today's default while widening what can be chosen.
  String? preferredDepositAccountId(Receivable? receivable);
}
```

`preferredDepositAccountId` exists so the two platforms cannot drift on the
default the way they drifted on the eligible set. It is the only place the
"prefer saved → prefer liquid → first" rule lives.

## UI Requirements

- **Web** — `_markReceived` gains a "Deposit to" `DropdownButtonFormField`
  directly mirroring the bill dialog's "Pay from": same position (above the
  "Already added to ledger" checkbox), same hide-when-`alreadyInLedger`
  behaviour, same disabled-when-empty handling. The confirmation sentence
  updates live as the selection changes, so the prose and the dropdown can
  never disagree.
- **Mobile** — `_MarkReceivedSheet` keeps its existing picker; only the account
  *list* and the initial selection move to the shared presenter helpers.
- **Add-forms** (both platforms) — the default-destination pickers use the same
  eligible set, so a stored default can never be an account the settle step
  would reject.
- **States:** unchanged. No account at all → the existing "Add an account
  before marking received" error still applies.
- **Thumb zone:** mobile is unchanged; its picker already sits in the sheet's
  action area.
- **Glanceability:** the destination stays visible in the confirmation sentence.
- **Micro-animations:** none added; dropdown uses the stock M3 transition.

## RPG Mechanics

N/A. Marking a receivable received awards nothing today and that is unchanged.

## Storage

No new `StorageService` keys, no cloud schema change. `Receivable.accountId` is
already persisted and synced.

## Edge Cases

- **Saved default is now archived / became a liability.** Not eligible, so the
  preference falls through to first-liquid → first-eligible. No dangling
  selection.
- **No eligible accounts at all.** Dropdown is omitted; the existing guard
  errors on confirm when recording in the ledger.
- **"Already added to ledger" checked.** No account is needed or recorded; the
  dropdown hides, matching the bill dialog exactly.
- **Only liability accounts exist.** Treated as "no eligible accounts" — better
  than silently recording income against a credit card.
- **Receivable whose default is a savings account.** Now selectable on web,
  where it previously could not even be reached.
- **Existing receivables with a liability `accountId` stored.** Possible from
  mobile's old unrestricted picker. The preference rejects it and falls
  through; the stored value is left alone rather than migrated, since it is
  harmless once unused.

## Non-Goals

- **Changing what "received" means for liabilities.** Recording a reimbursement
  *against* a credit card is a transfer/paydown, not an inflow;
  `quickPayCard` already covers that flow and is untouched.
- **Splitting a receipt across accounts.**
- **Changing the default-account rule itself** beyond centralising it — today's
  default stays today's default.

## Acceptance Criteria

`[test]` = covered by an automated test. `[inspect]` = verified by code review
only — the dialog bodies are inline in the page widgets with no existing
widget-test harness for them.

- [x] `[test]` `depositAccountsFor` returns active, non-liability accounts and
      excludes archived and liability accounts; empty when only liabilities
      exist.
- [x] `[test]` `preferredDepositAccountId` prefers the saved account when
      eligible, else the first liquid, else the first eligible, else null — and
      ignores a saved account that is archived or a liability.
- [x] `[inspect]` Web's mark-received dialog offers a "Deposit to" dropdown, and
      the confirmation sentence is recomputed inside the builder so it tracks
      the selection.
- [x] `[inspect]` The web dropdown hides when "Already added to ledger" is
      checked, and null is passed for the account in that case.
- [x] `[inspect]` A savings account is selectable as a receivable destination on
      web (follows from `depositAccountsFor`, which is `[test]`).
- [x] `[inspect]` Mobile's picker and initial selection use the shared helpers.
- [x] `[inspect]` Both add-forms offer the same eligible set as the settle step.
- [x] `flutter analyze` clean (no new errors or warnings); `flutter test` green.

### Also changed while here

Web's mark-received now wraps `markReceivableReceived` in try/catch and surfaces
a failure, matching the bill flow. It previously awaited the call bare, so an
error would leave the receivable silently unreceived with no feedback.
