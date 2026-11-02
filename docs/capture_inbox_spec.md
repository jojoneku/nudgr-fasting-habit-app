# Capture Inbox Spec

Plan: [.claude/plans/070-capture-inbox.md](../.claude/plans/070-capture-inbox.md)

## Overview

Bank and e-wallet apps post a notification for every payment. On Android,
Nudgr reads those notifications, parses each one into a draft transaction,
and files the draft in the **Capture Inbox** next to the Ledger. The user
fills in what the parser could not, then taps **Approve** or **Decline** on
each row. Nothing reaches the ledger without a tap.

Phase 1 (this spec) covers Android notifications only. Email arrives later
through the share sheet; iOS has no notification-listener API.

## User Story

> I paid for lunch with GCash and forgot to log it. When I open Nudgr that
> evening the Ledger shows `Inbox · 3`. Each row already has the amount, the
> merchant, the GCash account and the time. One needs a category. I pick it,
> tap Approve three times, and the ledger is caught up.

## Conceptual Model

### Three boundaries, one job each

| Boundary | Code | Job |
|---|---|---|
| Native listener | `TransactionNotificationListener.kt`, `CaptureQueue.kt` | Keep allowlisted apps, drop duplicates, append raw captures to a device queue. Never parses, never touches app data. |
| Parser | `lib/utils/capture_parser.dart`, `capture_templates.dart` | Pure function: raw text → `CapturedTransaction` with a `ParsedTransaction` draft. |
| Presenter | `lib/presenters/capture_inbox_presenter.dart` | Owns inbox rows. Drains the queue, parses, approves through the ledger, declines, undoes, purges. |

The ledger stays the owner of transactions. Approve builds a record and calls
`LedgerPresenter.addTransaction` or `addTransfer`.

### Parsed is not posted

A row with every field filled still waits for a tap. *Approve all ready*
posts every complete row, and that is a tap too. This is the same rule
Plan 065 set for Nudgy.

### Resolution order (parser)

1. Per-app template (direction + amount + counterparty + last-4).
2. Generic pass: first amount that is not a balance, direction cue word,
   counterparty after `to` / `at` / `from`, masked card suffix.
3. Account: last-4 map, else per-source default.
4. Transfer: a counterparty naming another of the user's accounts turns the
   row into a transfer with the reserved transfer category.
5. Category: personal dictionary, then category list by name.
6. Date: the notification's post time.

Confidence: 1.0 template, 0.6 generic with direction, 0.3 amount only,
0 no amount.

## Data Model

`CapturedTransaction` (`lib/models/finance/captured_transaction.dart`):
id, source, sourceApp, sourceLabel, capturedAt, rawTitle, rawText,
fingerprint, draft (`ParsedTransaction`), confidence, accountLast4, status
(`pending | approved | declined`), resolvedAt, transactionId, updatedAt.
`isReady` = `draft.isComplete`; `missing` lists the unfilled structured
fields.

`CaptureSettings` (`capture_settings.dart`): enabled, sources, sourceLabels,
accountBySource, accountByLast4, lastCaptureAt, lastDrainAt.

## Presenter / Service API

`CaptureInboxPresenter`: `pending`, `pendingCount`, `readyCount`,
`recentlyResolved`, `settings`, `accessGranted`, `listenerLooksAsleep`,
`hasPresence`, `isPossibleDuplicate(c)`, `sourceRows`; `load()`,
`refreshAccess()`, `drain()`, `fileRaw()`, `setDraft()`, `approve()`,
`approveAllReady()`, `decline()`, `declineAll()`, `undo()`, `setEnabled()`,
`setSourceEnabled()`, `setSourceAccount()`, `setLast4Account()`,
`recentApps()`, `openAccessSettings()`, `requestRebind()`.

`CaptureBridgeService` (`lib/services/capture_bridge_service.dart`) over
`MethodChannel('com.nudgr.app/capture')`: `isAccessGranted`,
`openAccessSettings`, `requestRebind`, `setAllowlist`, `drainRaw`, `requeue`,
`recentApps`, `lastConnectedAt`. `NullCaptureBridge` off Android.

## UI Requirements

- Ledger controls row: `Inbox` pill with a count badge. Hidden while capture
  is off and nothing is pending.
- Inbox page: rows grouped by day, newest first. Row = source · time, amount
  with direction glyph, description, account and category chips (an unfilled
  chip reads *Pick …* in the tertiary color), Decline (text) and Approve
  (filled, ≥ 44 px, disabled until ready with the missing field named).
  Swipe right approves, swipe left declines, both with Undo. Tapping the row
  body opens the edit sheet, which saves the draft only.
- Empty states: unsupported, off (*Turn on capture*), no access (*Enable
  notification access*), nothing pending (with last capture time).
- Settings ▸ Capture transactions: master toggle (disclosure sheet first),
  status card (access / asleep / listening), sources with default account,
  *Add from recent notifications*, learned card suffixes, privacy line.
- Theme colors only; dark and light.

## RPG Mechanics

None new. Approve routes through `addTransaction`, so the existing
first-log-of-the-day XP applies once. Approve and Decline award nothing.

## Storage

- `finance_capture_inbox` (user-scoped, synced as `finance_records` table
  `finance_capture_inbox`).
- `finance.captureSettings` (user-scoped, **not** synced — access is per
  device).
- Native: `capture_queue` SharedPreferences file — queue (cap 500),
  allowlist, recent fingerprints (200), recent apps (7 days), timestamps.

## Edge Cases

- Group summaries and ongoing notifications are skipped at the listener.
- Fingerprint = package + text + 2-minute bucket; declined rows are kept
  30 days so a re-post does not return; approved rows are kept 7 days for
  Undo and history.
- A failed persist on drain pushes the raw captures back to the native queue.
- Android 13+ marks notification access for a sideloaded app as a restricted
  setting; the disclosure sheet explains the extra step.
- The listener may be killed by OEM battery managers; `lastConnectedAt`
  older than 24 h shows *Reconnect*.
- Two accounts on one phone: the device queue is drained into the signed-in
  user's scoped inbox; rows sync so a sign-out wipe does not lose them.

## Acceptance Criteria

See plan §10. In short: nothing happens while capture is off; a payment made
while the app is closed appears on next open; Approve posts exactly one
record and moves the balance once; Undo reverses it; Decline dedupes a
re-post; transfers post two legs; non-allowlisted apps are never stored;
web build and release shrinker are unaffected.

## Parser Rules Learned From Public Parsers (2026-11-02)

Studied: `danrave1234/paytsek` (GCash / Maya / GoTyme / MariBank fixtures,
reject-first filter, redacted-shape capture), `frenzeldarzadon-code/wavewallet`
(GCash Express Send, InstaPay / PESONet credits), `adolf94/ArFinanceApp` (BPI,
VYBE, UnionBank regexes), `kiano8/InstantCrew`, `Patkik/Kipit`,
`icedamericanodev/Salapify`. None is a drop-in; each contributed shapes or a rule:

- **Reject first.** An OTP / security prompt, a promo or product nudge, a bill
  reminder, and a failed / pending / reversed transaction never become a row
  (`captureRejectReason`). `cashback` and `refund` are money in and stay.
- **Title is a signal.** GoTyme (*Transfer received*), Maya (*Money received*),
  MariBank (*Successful Incoming Transfer*) carry the meaning in the title.
- **Bare amounts.** Maya and some GCash InstaPay pushes print `500.00` with no
  currency mark; a two-decimal number straight after a money verb counts.
- **Whose suffix.** `ending 1234` after `from … account` or `to … account`
  is the other party's; only a suffix after `your` (no `to` / `from` between)
  maps to one of the user's cards.
- **Own instrument is not a transfer.** `using your Maya card` names the source
  side, so a whole-name account mention right after `your` never makes a
  transfer.
- **Names keep initials, lose phones.** `A. Santos` stays; `JUAN D. 0917…` and
  `MI*A P. 0915••••847` drop the number.
- **Package names** were checked against Google Play: BDO Online is
  `ph.com.bdo.retail` (plus `ph.com.bdo.pay`), GoTyme is `ph.com.gotyme`,
  SeaBank and MariBank are one app `ph.seabank.seabank`, VYBE by BPI is
  `com.indivara.bpi`, ShopeePay rides the Shopee app `com.shopee.ph`.
- Template provenance (`[real]` / `[sms]` / `[guess]`) is annotated in
  `lib/utils/capture_templates.dart`. BDO, UnionBank push wording and all
  outgoing GoTyme shapes still need a real sample.
- Worth borrowing later: paytsek's **redacted-shape export** (digits → `#`,
  letters → `a`/`A`) so a user can share an unknown template without
  exposing values.

### Google Wallet (added 2026-11-02)

Package `com.google.android.apps.walletnfcrel`. One field is the payment line
(`₱150.00 with Visa •••• 1234`, `UAH198.00 with Visa PrivatBank ••6810`,
`12,34 € · Mastercard •• 4321`) and the other is the merchant, in either order.
Wallet only posts purchases, so a row is always money out; a notification with
no payment line (card added, pass updated) is dropped. The card label names the
user's own card: the learned suffix wins, else an account whose name appears in
the label (`with BPI Credit Card •••• 9999`), else the source default. The label
is never scanned as a transfer destination. Shapes come from
`tiberiusteng/financisto1-holo`, `PhilippSchmid98/Stutz`, `kodalus/Castellan`;
no PH sample yet.

### GoTyme real samples (user, 2026-11-02)

- `Transfer successful` / `You sent P4000.00 to <name> Bank Of The Philippine
  Islands (BPI) ••••••1637.` → the counterparty runs up to the mask; the bank
  code in brackets names the user's BPI account by its distinct word, so the
  row is a transfer GoTyme → BPI.
- `GoalSave: Funds transferred` / `You've transferred P3,500.00 from GoalSave
  Tuition Fund to your Deposit account...6634. 02 Nov 20:42.` → money in to the
  deposit account from the pocket; `...6634` after `your` is the user's own
  suffix. The pocket becomes a transfer source only when it is one of the
  user's accounts.

### Email (open question, 2026-11-02)

A bank email also reaches the phone as a Gmail notification (`com.google.android.gm`,
title = sender such as `BPI InstaPay`, text = the first lines of the email). The
same listener can capture it if the native allowlist filters Gmail by sender
keyword, so personal mail never enters the queue. Whether the amount is inside
the notification text is unverified; the BPI InstaPay sample cuts off before
the amount. Gmail API stays deferred (restricted scope, CASA). AI is not a
filter: at most a fallback for a bank-sourced row the templates could not
finish, behind Cloud AI (plan phase 2).

### Gmail as a source, filtered to BPI (built 2026-11-02)

- Package `com.google.android.gm` is a preset with a **sender filter**:
  `CaptureSettings.senderFilters[gmail] = ['BPI']`. The native listener keeps a
  Gmail notification only when its title (the sender) contains one of the
  words; everything else is dropped unstored. The filter crosses the channel
  with the allowlist (`setAllowlist({packages, titleFilters})`); the old bare
  list is still accepted.
- A Gmail row is labelled by the sender (`BPI InstaPay`), described by the
  subject line when no counterparty is found, and defaults to the BPI account.
- Templates: `Incoming/Outgoing Interbank Funds Transfer` set the direction;
  `Transfer From <bank>` names a transfer source; `Amount PHP 4,000.00` is a
  guess until a full email head is seen. A template without an `amount` group
  fixes the direction only and leaves the row at 0.6 for the generic amount.
- The notification carries only the head of the email; the first real sample
  cut off before the amount, so such a row arrives with `Needs amount`.

### One payment, two notifications (built 2026-11-02)

A tap-to-pay through Google Wallet is also reported by the card's own app, and
a bank push may be echoed by its email. `CaptureInboxPresenter.twinOf` marks a
pending row whose amount matches an earlier pending row from a *different*
source within 15 minutes (direction must agree when both are known). The row
shows `Same as <source>`. Approving either row posts once and declines the
twin with the same `resolvedAt` stamp; Undo of that approve brings the twin
back. `Approve all ready` therefore posts one record per payment. Rows with no
amount (a truncated email) cannot be twinned and stay for the user.
