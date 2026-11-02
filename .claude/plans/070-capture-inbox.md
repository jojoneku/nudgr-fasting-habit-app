# Plan 070 — Capture Inbox: transactions from Android notifications (email later)

**Goal:** when a bank or e-wallet app posts a notification about money moving,
Nudgr captures it on-device, parses it into a draft transaction, and files the
draft in a **Capture Inbox** next to the Ledger. The user opens the inbox when
they want, fills in what the parser could not, and taps **Approve** or
**Decline** per row. Nothing is ever written to the ledger without a tap.

**Why an inbox and not a card:** a suggestion card interrupts, and it shows one
item at a time. A bucket lets 5 GCash payments from a busy day wait together,
and the user clears them in one sitting. It also matches the rule Plan 065 set
for Nudgy: *resolved is not confirmed*.

**Platform:** Android only in phase 1. iOS has no notification-listener API.
Web shows the inbox read-only in phase 3 at the earliest.

**Status:** plan authored 2026-11-02. Nothing built.

---

## 1. Conceptual model

```
 bank / e-wallet app
        │  posts a notification
        ▼
 ┌─────────────────────────────┐   native, always on, no Flutter engine
 │ TransactionNotificationListener │  • package allowlist (drop the rest at once)
 │ (NotificationListenerService)   │  • dedupe by fingerprint
 └─────────────┬───────────────┘  • append raw capture to a device-level queue
               │
               ▼  on app foreground / inbox open
 ┌─────────────────────────────┐   Dart
 │ CaptureBridgeService.drainRaw│ ──▶ CaptureParser (pure) ──▶ CapturedTransaction
 └─────────────────────────────┘                                  (status: pending)
               │
               ▼
 ┌─────────────────────────────┐   owner of inbox items
 │ CaptureInboxPresenter       │  approve(id) ──▶ LedgerPresenter.addTransaction
 └─────────────────────────────┘  decline(id) ──▶ tombstone, kept 30 days
               │
               ▼
 Ledger header pill "Inbox · 3"  ▸  CaptureInboxView (list, approve / decline)
 Dashboard card (mirrors pendingCount off the presenter)
```

Three boundaries, each with one job:

1. **Native listener** reads, filters and queues. It never parses and never
   touches app data. It is the only code that sees notifications from other
   apps, so it is the smallest piece possible.
2. **CaptureParser** is a pure Dart function from raw text to a draft. It is
   fully unit-tested against real (redacted) notification strings.
3. **CaptureInboxPresenter** owns the inbox items. The ledger stays the owner
   of transactions; approval hands a record to `ledger.addTransaction`, which is
   also where XP already lives.

### The same rule as Nudgy: parsed is not posted

A fully-resolved capture still waits for a tap. The inbox exists to be the
confirm surface. The only shortcut is **Approve all ready**, which posts every
row whose five required fields are filled, and even that is a tap.

---

## 2. What the user sees

### Entry points
- **Ledger header pill**: `Inbox · 3` to the right of the month controls in
  `_LedgerControlsRow`. Hidden when capture is off *and* the inbox is empty.
- **Dashboard card** (phase 2): "3 captured transactions waiting" with a
  *Review* action. The dashboard reads the count off the inbox presenter by
  listener, never a copy (Rule 8).
- **Settings ▸ Treasury ▸ Capture transactions**: master toggle, system access
  status, sources list, account mapping, privacy note.

### CaptureInboxView (full-screen route)
- Rows grouped by capture day, newest first.
- Each row: source app name + time, amount (large), direction glyph
  (in / out / transfer), merchant or payee, then two chips: **account** and
  **category**. A chip the parser could not fill reads *Pick account* /
  *Pick category* in the tertiary color. Tapping a chip opens the same picker
  the Add Transaction sheet uses. Tapping the row body opens
  `AddTransactionSheet(prefill: draft)` for full editing; saving there approves
  the row.
- Row actions, bottom-right of the row, each ≥ 44×44: **Decline** (text) and
  **Approve** (filled). Approve is disabled while a required field is missing;
  the disabled hint names the field ("needs category").
- Swipe right = approve (only when ready), swipe left = decline. Both show an
  `AppToast` with **Undo** (5 s). Undo of an approve deletes the posted
  transaction through the ledger.
- App bar: **Approve all ready (n)** when n > 0. Overflow: *Decline all*,
  *Sources…*.
- A *possible duplicate* badge when the ledger already has a record with the
  same amount, same date and same account (phase 2).
- Empty states:
  - access not granted → explanation + *Enable notification access* button;
  - granted, nothing pending → "Nothing to review" + "Last capture: 2 h ago"
    (or "never"), which doubles as the diagnostic that the listener is alive.

### Settings ▸ Capture transactions
- **Master toggle.** Turning it on first shows a disclosure sheet (what is read,
  what is stored, that only allowlisted apps are kept), then opens the system
  *Notification access* page. On Android 13+ a sideloaded (OTA) app is a
  *restricted setting*: the sheet explains the extra step (App info ▸ ⋮ ▸ Allow
  restricted settings) before the system page opens.
- **Sources.** Seeded presets (GCash, Maya, BPI, UnionBank, BDO, SeaBank,
  MariBank, GoTyme, ShopeePay) plus *Add from recent notifications*: the native
  side keeps a small ring of `(package, appLabel)` for apps that posted a
  notification in the last 7 days. Labels only, no text. Package names of the
  presets are verified at implementation, not assumed.
- **Per source: default account.** GCash → the user's GCash account, and so on.
  A banking app that notifies for several cards can map by the last 4 digits
  when the notification carries them (`accountByLast4`).
- **Privacy line:** "Notification text stays on this phone. It is sent to the
  cloud only when Cloud AI is on, and only for rows the parser could not
  finish."

---

## 3. Data model

### `lib/models/finance/captured_transaction.dart` (new)

```dart
enum CaptureSource { androidNotification, share, email }
enum CaptureStatus { pending, approved, declined }

/// One captured money event, from first sight to approve/decline.
/// Immutable; fromJson/toJson; no logic beyond `isReady`.
class CapturedTransaction {
  final String id;
  final CaptureSource source;
  final String sourceApp;        // package name, or 'share' / mail domain
  final String sourceLabel;      // app label shown in the row ("GCash")
  final DateTime capturedAt;     // notification postTime
  final String rawTitle;
  final String rawText;          // what the parser read; shown on tap
  final String fingerprint;      // dedupe key (see §5)
  final ParsedTransaction draft; // amount, type, accountId, categoryId,
                                 // description, date, note, transferToAccountId
  final Set<EntryField> missing; // what the user still has to supply
  final double confidence;       // 0..1 from the parser
  final String? accountLast4;    // when the text carried a masked card number
  final CaptureStatus status;
  final DateTime? resolvedAt;
  final String? transactionId;   // ledger record created on approve
  final DateTime updatedAt;

  bool get isReady =>            // the five fields addTransaction needs
      draft.amount != null && draft.type != null &&
      draft.accountId != null && draft.categoryId != null && draft.date != null;
}
```

`ParsedTransaction` and `EntryField` already exist
(`finance_parse_result.dart`, `extracted_entry.dart`), so the inbox speaks the
same draft type as chat, voice and receipt scan.

### `lib/models/finance/capture_settings.dart` (new)

```dart
class CaptureSettings {
  final bool enabled;
  final Set<String> sources;                   // allowlisted packages
  final Map<String, String> accountBySource;   // package → accountId
  final Map<String, String> accountByLast4;    // "1234" → accountId
  final DateTime? lastCaptureAt;
  final DateTime? lastDrainAt;
}
```

Settings are **per device** (notification access is granted per device), so
they are stored locally and never synced.

### Raw capture (native → Dart, transient)

```json
{ "pkg": "com.globe.gcash.android", "label": "GCash", "postTime": 1762070400000,
  "title": "Payment sent", "text": "You have sent PHP 285.00 to JOLLIBEE ...",
  "fp": "sha1(pkg|text|postTime/120000)" }
```

---

## 4. Affected files

| File | Action | Layer |
|---|---|---|
| `lib/models/finance/captured_transaction.dart` | Create | Model |
| `lib/models/finance/capture_settings.dart` | Create | Model |
| `lib/utils/capture_parser.dart` | Create | Utils (pure) |
| `lib/utils/capture_templates.dart` | Create | Utils (per-app regex templates) |
| `lib/services/capture_bridge_service.dart` | Create | Service (MethodChannel) |
| `lib/services/storage_service.dart` | Modify | Service (2 keys, 4 methods) |
| `lib/services/local_storage_service.dart` | Modify | Service |
| `lib/services/sync_service.dart` | Modify | Service (`capture_inbox` table name) |
| `lib/presenters/capture_inbox_presenter.dart` | Create | Presenter |
| `lib/presenters/treasury_presenters.dart` | Modify | Presenter graph |
| `lib/presenters/treasury_dashboard_presenter.dart` | Modify (phase 2) | Presenter |
| `lib/views/treasury/ledger/ledger_view.dart` | Modify | View (inbox pill) |
| `lib/views/treasury/capture/capture_inbox_view.dart` | Create | View |
| `lib/views/treasury/capture/capture_row.dart` | Create | View |
| `lib/views/treasury/capture/capture_disclosure_sheet.dart` | Create | View |
| `lib/views/settings/capture_settings_section.dart` | Create | View |
| `lib/views/home_screen.dart` | Modify | Shell (drain on resume) |
| `android/app/src/main/kotlin/com/nudgr/app/TransactionNotificationListener.kt` | Create | Native |
| `android/app/src/main/kotlin/com/nudgr/app/CaptureQueue.kt` | Create | Native |
| `android/app/src/main/kotlin/com/nudgr/app/MainActivity.kt` | Modify | Native (channel) |
| `android/app/src/main/AndroidManifest.xml` | Modify | Native (service) |
| `android/app/src/main/res/raw/keep.xml` | Modify | Native (listener class kept by shrinker) |
| `test/utils/capture_parser_test.dart` | Create | Test |
| `test/presenters/capture_inbox_presenter_test.dart` | Create | Test |
| `test/views/capture_inbox_view_test.dart` | Create | Test |
| `docs/capture_inbox_spec.md` | Create | Spec |

No Supabase migration: inbox rows ride the existing `finance_records` JSONB
table with `table_name = 'capture_inbox'`.

---

## 5. Interface definitions

### Native (Kotlin)

```kotlin
// TransactionNotificationListener : NotificationListenerService
//  onNotificationPosted(sbn):
//    - drop if sbn.packageName !in allowlist          (read from prefs each call)
//    - drop if FLAG_GROUP_SUMMARY or FLAG_ONGOING_EVENT
//    - text = extras BIG_TEXT ?: TEXT; title = extras TITLE
//    - fp = sha1(pkg + "|" + text + "|" + postTime / 120_000)   // 2-min bucket
//    - CaptureQueue.append(raw) if fp not in recent fingerprints (ring of 200)
//    - record (pkg, label, postTime) in the "recent apps" ring (labels only)
//  onListenerConnected(): write lastConnectedAt
//
// CaptureQueue: JSON array in app-private file, append-only until drained.
//  Hard cap 500 entries; oldest dropped first. Never user-scoped: the device
//  queue is drained into the signed-in user's inbox by Dart.
//
// MethodChannel "com.nudgr.app/capture"
//  isAccessGranted()           -> Boolean   (NotificationManager.isNotificationListenerAccessGranted)
//  openAccessSettings()        -> Unit      (ACTION_NOTIFICATION_LISTENER_SETTINGS)
//  requestRebind()             -> Unit      (NotificationListenerService.requestRebind)
//  setAllowlist(List<String>)  -> Unit
//  drainRaw()                  -> List<Map> (returns and clears the queue atomically)
//  recentApps()                -> List<Map> ({pkg, label, lastSeen})
//  lastConnectedAt()           -> Long?
```

Manifest:

```xml
<service android:name=".TransactionNotificationListener"
    android:exported="true"
    android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">
  <intent-filter>
    <action android:name="android.service.notification.NotificationListenerService"/>
  </intent-filter>
</service>
```

### `CaptureBridgeService` (Dart)

```dart
class CaptureBridgeService {
  Future<bool> isAccessGranted();
  Future<void> openAccessSettings();
  Future<void> requestRebind();
  Future<void> setAllowlist(Set<String> packages);
  Future<List<RawCapture>> drainRaw();      // [] on web / iOS / MissingPlugin
  Future<List<RecentApp>> recentApps();
  Future<DateTime?> lastConnectedAt();
}
```

A `NullCaptureBridge` returns empty values so the presenter needs no platform
checks (same pattern as `NullAiCoachService`).

### `CaptureParser` (pure)

```dart
CapturedTransaction parseCapture(
  RawCapture raw, {
  required CaptureSettings settings,
  required List<FinancialAccount> accounts,
  required List<FinanceCategory> categories,
  required FinancePersonalDictionary? dict,
  required DateTime now,
});
```

Order of resolution, each step only fills what is still null:

1. **Template** for `raw.pkg` (`capture_templates.dart`): named regex groups
   `amount`, `direction`, `counterparty`, `last4`, `ref`. One template list per
   app, tried in order. Templates are data, so adding a bank is one entry.
2. **Generic fallback**: amount = first `(₱|PHP|Php|P)\s?[\d,]+(\.\d{2})?`;
   direction from cue words (`sent|paid|purchase|debited|withdraw` → outflow,
   `received|credited|refund|cash in` → inflow); counterparty after
   `to|at|from`.
3. **Account**: `settings.accountByLast4[last4]`, else
   `settings.accountBySource[pkg]`.
4. **Transfer detection**: if the counterparty fuzzy-matches another of the
   user's account names (reuse `_matchAccountInText` logic exported as a public
   helper), set `type = transfer`, `transferToAccountId`, and category to the
   transfer category.
5. **Category**: `dict.lookup(counterpartyToken)`, then the keyword-to-category
   resolver the chat parser already uses (`_resolveCategoryToken`, exported).
6. **Date**: `postTime` day. Notifications arrive in real time, so this is
   right far more often than the chat parser's "yesterday" guesses.
7. `confidence`: 1.0 template hit, 0.6 generic hit, 0.3 amount only.
   `missing` = whichever of the five required fields is still null.

Cloud enrichment (phase 2, only when `SettingsPresenter.useCloudAi`): one
`extractFinanceEntries` call per drain over the rows that are still missing a
category or have `confidence < 0.6`. Same prompt contract as Plan 058. Rows that
come back resolved are updated; the user still approves.

### `CaptureInboxPresenter` (owner of inbox items)

```dart
class CaptureInboxPresenter extends ChangeNotifier {
  CaptureInboxPresenter(StorageService storage, LedgerPresenter ledger,
      CaptureBridgeService bridge, {FinancePersonalDictionary? dict,
      AiCoachService? cloudAi, SettingsPresenter? settings});

  // state
  List<CapturedTransaction> get pending;        // status == pending, newest first
  List<CapturedTransaction> get recentlyResolved; // last 7 days, for Undo + history
  int get pendingCount;
  int get readyCount;                            // pending && isReady
  CaptureSettings get settings;
  bool get accessGranted;                        // last probe
  DateTime? get lastCaptureAt;
  bool get isDraining;
  bool isPossibleDuplicate(CapturedTransaction c); // phase 2

  // lifecycle
  Future<void> load();
  Future<void> refreshAccess();   // probe isAccessGranted; on resume
  Future<int> drain();            // pull raw, parse, append pending; returns new count

  // review
  Future<void> setDraft(String id, ParsedTransaction edited); // chip edits / sheet
  Future<TransactionRecord> approve(String id);               // requires isReady
  Future<int> approveAllReady();
  Future<void> decline(String id);
  Future<void> declineAll();
  Future<void> undo(String id);   // approved → delete ledger record, back to pending
                                  // declined → back to pending

  // settings
  Future<void> setEnabled(bool v);      // false also calls bridge.setAllowlist({})
  Future<void> setSourceEnabled(String pkg, String label, bool v);
  Future<void> setSourceAccount(String pkg, String? accountId);
  Future<void> setLast4Account(String last4, String? accountId);
  Future<List<RecentApp>> recentApps();
  Future<void> openAccessSettings();
}
```

Rules the presenter enforces:

- `approve` builds a `TransactionRecord` from the draft and calls
  `ledger.addTransaction` (transfers call `ledger.addTransfer`). It then stores
  `transactionId` so `undo` can call `ledger.deleteTransaction`.
- Approve awards **no extra XP**. The ledger's own first-of-day XP applies
  because the record goes through `addTransaction`. Decline awards nothing.
- The presenter **subscribes to the ledger** for accounts and categories (it
  mirrors, never copies on `load()` only), so a chip picker always lists the
  live accounts.
- Items older than **30 days** with status `declined`, or `approved` older than
  **7 days**, are purged on `load()`. Declined fingerprints stay in a small
  set for 30 days so a re-posted notification does not come back.
- `drain()` is idempotent: the native queue is cleared only after the parsed
  rows are persisted. If persist fails, the raw rows are pushed back.
- Mutate → notify → persist (Plan 041).

### `StorageService`

```dart
static const String keyCaptureInbox    = 'finance_capture_inbox';   // user-scoped, synced
static const String keyCaptureSettings = 'finance.captureSettings'; // user-scoped, NOT synced

Future<List<CapturedTransaction>> loadCaptureInbox();
Future<void> saveCaptureInbox(List<CapturedTransaction> items);
Future<CaptureSettings> loadCaptureSettings();
Future<void> saveCaptureSettings(CaptureSettings s);
```

Sync: `SyncDomain.financeRecord`, key `capture_inbox/<id>`, bulk-upserted with
the other finance records (PR #268 batching). Syncing the inbox keeps it across
the sign-out wipe and lets the web show it in phase 3.

### `TreasuryPresenters`

```dart
final CaptureInboxPresenter captureInbox;   // built after ledger; before dashboard
// factory gains: CaptureBridgeService? captureBridge  (mobile passes the real one,
// web passes null → NullCaptureBridge)
```

The dashboard (phase 2) takes `captureInbox` and mirrors `pendingCount` in a
`_syncFromCaptureInbox` listener, same shape as `_syncFromBills`.

---

## 6. Implementation order

Each phase is its own PR against `dev`. Format gate (`dart format`, analyzer,
tests) before every push.

### Phase 1 — the inbox works end to end (Android)
1. [ ] Models `CapturedTransaction`, `CaptureSettings` + JSON round-trip tests.
2. [ ] `StorageService` keys and methods; `LocalStorageService` impl; sync table
       name `capture_inbox` registered in push and pull.
3. [ ] `capture_templates.dart` + `capture_parser.dart` with a fixture file of
       redacted real notifications (GCash, Maya, BPI at least). Tests cover
       amount formats (`PHP 1,250.00`, `₱285`, `P 1250`), both directions,
       transfer to own account, last-4 mapping, generic fallback.
4. [ ] Native: `CaptureQueue`, `TransactionNotificationListener`, manifest
       service, `keep.xml` entry, MethodChannel methods on `MainActivity`.
5. [ ] `CaptureBridgeService` + `NullCaptureBridge`.
6. [ ] `CaptureInboxPresenter` with FakeStorage tests: drain, approve → ledger
       record + balance delta, decline, undo both ways, purge, access probe.
7. [ ] Wire into `TreasuryPresenters`; `home_screen.dart` calls
       `refreshAccess()` + `drain()` on resume and on first load.
8. [ ] Views: disclosure sheet, settings section, inbox view + row, ledger pill.
9. [ ] Spec `docs/capture_inbox_spec.md`; CLAUDE.md "Active Specs" link.
10. [ ] Device verification on a real phone (not the emulator — see Plan 039
        notes): grant access, pay with GCash, open app, row appears, approve,
        ledger shows it, balance moved once.

### Phase 2 — quality
- [ ] Dashboard card mirroring `pendingCount`.
- [ ] Duplicate badge against ledger (same amount, date, account).
- [ ] Cloud enrichment batch behind `useCloudAi`.
- [ ] Native quiet summary notification "n transactions waiting" (own channel,
      low importance, once per 6 h at most), tap deep-links to the inbox via
      the existing `WidgetRoute` pattern.
- [ ] "Listener looks asleep" diagnostic: `lastConnectedAt` older than 24 h
      while enabled → banner with *Reconnect* (`requestRebind`) and the OEM
      battery-whitelist hint.

### Phase 3 — email and web
- [ ] **Share to Nudgr**: `ACTION_SEND text/plain` intent filter. A shared
      email body (or any text) enters the same inbox with
      `source = share`, parsed by the generic path plus mail-receipt templates
      (Grab, Shopee, Lazada, bank statements). Cheapest email path, no OAuth.
- [ ] Web: read-only inbox page in Treasury web (rows synced), approve/decline
      allowed since the ledger lives there too. Capture itself stays Android.
- [ ] Gmail API: **deferred**. The `gmail.readonly` scope is *restricted*;
      Google requires an annual third-party CASA assessment before a public
      app may use it. Revisit only if share-to-inbox proves insufficient. The
      alternative is a forward-to address handled by the Lambda (SES inbound →
      parse → insert `capture_inbox` row via service role), which is a
      backend project of its own.

---

## 7. RPG impact

- No new XP, no new quest. Approval posts through `ledger.addTransaction`, so
  the existing *first log today* bonus can fire once per day as before.
- No XP for approve or decline on purpose: the 2026-07-04 audit already lists
  4 farmable XP paths, and an inbox that pays per tap would be a fifth.
- One new notification channel in phase 2 (`capture_summary`, low importance).
  It is subject to the master notification toggle like every other channel.

---

## 8. Risks and edge cases

| Risk | Mitigation |
|---|---|
| Notification access reads **every** app's notifications | Filter by allowlist inside `onNotificationPosted` before anything is stored. Non-allowlisted apps leave only `(package, label)` in the recent-apps ring. Raw text is never logged. Disclosure sheet before the system page. |
| Android 13+ blocks notification access for sideloaded apps ("Restricted setting") | Disclosure sheet explains App info ▸ Allow restricted settings. Settings section shows *Access: blocked* with that hint when `isAccessGranted` stays false after return. |
| OEM battery managers kill the listener (Xiaomi, Huawei, Oppo) | `lastConnectedAt` diagnostic, *Reconnect* via `requestRebind`, vendor whitelist hint. Queue is a file, so a killed service loses nothing already captured. |
| Same event posted twice (push + in-app, or group summary + child) | Skip `FLAG_GROUP_SUMMARY`; fingerprint = package + text + 2-minute bucket; recent-fingerprint ring of 200 on the native side; declined fingerprints kept 30 days in Dart. |
| User already logged it through chat before opening the inbox | Phase 2 duplicate badge. Approve is still allowed; the user decides. |
| Bank app notifies for debit **and** credit card | `accountByLast4` map wins over `accountBySource`. Unmapped last-4 leaves account empty and the chip asks. |
| Transfers between own accounts counted as spend | Counterparty matched against own account names → `transfer`, two legs through `ledger.addTransfer`, `transferGroupId` set, so every spend aggregation guard still holds. |
| Installment purchases, bill payments, reimbursables | Out of scope for the parser. Approve as a regular record; the ledger already offers convert-to-installment and mark-reimbursable afterwards. |
| Native queue is device-level; two accounts on one phone | Drain stamps rows into the signed-in user's scoped inbox. With no user signed in the queue is left alone. Inbox rows sync, so a sign-out wipe does not lose pending reviews. |
| Shrinker strips the listener class in release (PR #218 history) | `keep.xml` entry and a release-build smoke test in the phase-1 device check. |
| Cloud enrichment sends notification text off-device | Only when `useCloudAi` is on, only for unresolved rows, never the allowlist or last-4 map; stated in the privacy line. |
| Web build breaks on the Android channel | Bridge lives behind an interface; web gets `NullCaptureBridge`; no `dart:io` in shared code. |

---

## 9. Out of scope

- iOS (no API). SMS reading (`READ_SMS` is Play-restricted and the wrong tool
  when the same banks push notifications). Gmail OAuth (see phase 3 note).
- Auto-posting of any kind, even at confidence 1.0.
- Learning: approving a row does **not** write to the personal dictionary by
  itself. A later change can add the same *learn this merchant* chip the chat
  path uses.
- Editing notification history already dismissed before access was granted.
  The listener sees only what is posted after it connects.

---

## 10. Acceptance criteria

- [ ] With capture off, the app has no listener behaviour, no pill, no card.
- [ ] Turning capture on shows the disclosure sheet, then the system access
      page; returning to the app updates the access status without restart.
- [ ] A GCash payment made while the app is closed appears in the inbox on next
      open, with amount, direction, merchant, date and the mapped account.
- [ ] A row missing a category shows *Pick category*; Approve is disabled and
      names the field; picking it enables Approve.
- [ ] Approve posts exactly one ledger record, the account balance moves once,
      the row leaves *pending*, and the ledger list shows the record without a
      reload.
- [ ] Undo within 5 s removes the posted record and restores the row.
- [ ] Decline removes the row; the same notification text re-posted within
      30 days does not return.
- [ ] A payment to one of the user's own accounts is proposed as a transfer and
      posts two legs with a shared `transferGroupId`.
- [ ] A notification from a non-allowlisted app is never persisted (verified by
      inspecting the queue file in a debug build).
- [ ] `flutter build web` succeeds and the web Ledger is unchanged.
- [ ] Release APK: the listener still receives after R8 shrinking.
- [ ] `dart format --set-exit-if-changed`, analyzer and the test suite pass.

---

*Present this plan for approval before writing any code.*
