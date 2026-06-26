# Data Security & Encryption Spec

> Status: **Draft / Plan** — authored 2026-06-26. Phased so each phase ships and
> verifies independently. Phases are ordered by *risk-adjusted value*: the
> earliest phases are backup-safe and need no data migration; the later phases
> require on-device QA before merge.

## 1. Why

Nudgr stores **health data** (weight, body measurements, activity) and
**financial data** (account balances, transactions, budgets, bills, debts). It
syncs to Supabase and runs an AI coach endpoint. The current posture:

- **In transit:** good. All sync / AI / edge-function calls use HTTPS + a
  per-user Supabase JWT (Google OAuth). No hardcoded secrets in source; the only
  value bundled into the web build is the public Supabase *anon* key.
- **At rest: not encrypted.** Every user-data key is plaintext JSON in
  `SharedPreferences` (`lib/services/local_storage_service.dart`). A full
  plaintext copy is written to `backup.json` (`lib/services/backup_service.dart`)
  and a full plaintext dump is uploaded to the Supabase `backups` table
  (`lib/services/snapshot_service.dart`). Android `allowBackup` defaults to
  **true**, so the plaintext store is swept into Google's cloud auto-backup.

This spec closes the at-rest gap and hardens trust, **without breaking the
existing backup/restore and cross-device sync**.

## 2. Hard constraints discovered in the codebase

These shape every decision below — violate them and we lose data or break features.

1. **Native widgets read `SharedPreferences` in plaintext.** `WidgetData.kt`
   reads keys via `all[key]` from Kotlin to render home-screen widgets, and a
   headless `home_widget` background isolate (no auth session) re-scopes storage
   to apply inline actions. **The widget-bridge keys must stay plaintext** and
   must be excluded from any encryption set.
2. **Cross-device restore depends on the Supabase snapshot/sync, not on the
   device.** Any client-side encryption of the *cloud* snapshot needs a key that
   survives reinstall / new device — i.e. derived from the user, not the device
   keystore. Encrypting the cloud snapshot with a device-local key would make it
   unrecoverable.
3. **A migration that misreads existing plaintext = mass data loss.** Encrypting
   the local store needs a crash-safe, idempotent, per-key migration (mirror the
   existing `_migrateUnscopedKeys` pattern in `local_storage_service.dart:73`).
4. **No Flutter SDK in the web/CI authoring environment.** At-rest encryption +
   migration must be validated on a real device/emulator (install old build →
   upgrade → confirm data intact → confirm widgets still render) before merge.
   CI alone is not sufficient sign-off for Phase 1+.

## 3. Backup-safety analysis (does this break backups?)

| Mechanism | File | Effect of this plan |
|---|---|---|
| Supabase table sync (real cross-device backup) | `sync_service.dart` | **Unchanged.** Encryption is at the local storage boundary; data is decrypted into memory and the same plaintext `Map` is serialized to JSON over HTTPS. Wire format and server tables unchanged. |
| Android OS auto-backup | `AndroidManifest.xml` | **Disabled** by Phase 0. Redundant for signed-in users (sync restores them). Narrow tradeoff: signed-out users lose reinstall recovery — mitigated by nudging sign-in. |
| Local `backup.json` safety net | `backup_service.dart` | **Still works**, now encrypted (Phase 0). Key durability handled explicitly (§Phase 0). |
| Cloud snapshot | `snapshot_service.dart` | Phase 2 only. The one place naive encryption breaks restore — requires user-bound key escrow (§Phase 2). Left plaintext-in-table (TLS + RLS) until that design lands. |

## 4. Phases

### Phase 0 — Backup hardening (no migration, low risk, CI-verifiable)

Goal: stop leaking plaintext sensitive data into platform cloud backups, and
encrypt the local backup file. Self-contained; touches no runtime data path.

- **Android:** `android:allowBackup="false"` on `<application>`; add
  `android:dataExtractionRules` (API 31+) and `android:fullBackupContent`
  resources that exclude `shared_prefs` and `backup.json` even if a future build
  re-enables backup.
- **iOS:** mark `backup.json` `isExcludedFromiCloudBackup`; set
  `NSFileProtectionComplete` so app files are unreadable while the device is
  locked.
- **Encrypt `backup.json`:** AES-GCM payload, data key in `flutter_secure_storage`
  (Keychain / Android Keystore-backed). `readBackup` transparently decrypts; on
  decrypt failure it returns `null` (same contract as today's parse failure).
  Key durability: the backup file's purpose is to survive a `SharedPreferences`
  wipe — secure-storage keys survive that, so the invariant holds. Document that
  a full keystore wipe (factory-style) invalidates the local backup; the cloud
  snapshot remains the durable recovery path.
- **Wire teardown:** `BackupService.deleteBackup()` is already implemented but
  unused — call it from the explicit "delete my data" / account-reset path
  (`clearUserData`), not from ordinary sign-out (which must keep the safety net).

Acceptance: existing `backup_service` tests pass; new round-trip test
(write→read encrypted) passes; manifest lints clean; CI green.

### Phase 1 — Encrypted local store at rest (needs device QA)

Goal: user-data keys in `SharedPreferences` encrypted at rest.

- **Crypto:** AES-256-GCM. Random 256-bit **data key (DEK)** generated once,
  stored in `flutter_secure_storage` (the DEK is wrapped by the OS keystore/
  Keychain = KEK). Use a vetted package (`cryptography` or `encrypt`); no
  hand-rolled crypto. Each value: `nonce || ciphertext || tag`, base64.
- **Choke point:** add `_putSecure`/`_getSecure` helpers in
  `LocalStorageService` and route the **user-data** string keys
  (`_kUserDataKeys`) through them. ~135 call sites — funnel via the helpers
  rather than touching each.
- **Stay plaintext (do NOT encrypt):**
  - Widget-bridge keys (`widget.*`, `w_*`) — read by native Kotlin / headless
    isolate (constraint #1).
  - Device-level keys (`themeMode`, `useCloudAi`, `aiPromptSkippedAt`).
  - Sync bookkeeping (`syncQueue`, `syncTimestamps`, `sync_initial_push_done_v2`).
- **Migration:** one-time, per-key, idempotent, crash-safe. On first launch
  post-upgrade, for each user-data key holding a plaintext value, re-write it
  encrypted and set a per-namespace `enc_migrated_v1` flag. Never delete the
  source until the encrypted write succeeds. Mirror `_migrateUnscopedKeys`.
- **Headless isolate:** confirm `flutter_secure_storage` reads the DEK from a
  background isolate (same app sandbox — expected to work; must be verified on
  device). The isolate must not need to decrypt widget data (kept plaintext).
- **Web:** `flutter_secure_storage` on web is weak; treat web as out of scope for
  at-rest encryption (browser storage is origin-sandboxed and the web build
  already warns against bundling secrets). Encrypt mobile only; no-op on web.

Acceptance (device): install pre-upgrade build with data → upgrade → all
presenters load intact → widgets render → sign-out/sign-in works → on-disk prefs
inspection shows ciphertext for user-data keys, plaintext for widget keys.

### Phase 2 — Cloud snapshot client-side encryption (needs key-escrow design)

The only change that can break cross-device restore if rushed (constraint #2).

- Encrypt the snapshot payload before upload to the `backups` table. The key
  **must be user-recoverable on a new device.** Recommended: a user passphrase →
  Argon2id/PBKDF2 → wrapping key that wraps the DEK; store the wrapped DEK
  server-side in `user_profile`. New device: user enters passphrase → unwrap DEK
  → decrypt snapshots. Include an explicit, documented recovery/lost-passphrase
  story (lost passphrase = encrypted snapshots unrecoverable — by design).
- Regular table sync stays TLS + RLS (not E2E) so server-side features
  (multi-device merge, future server logic) keep working. Revisit field-level
  encryption for finance/health columns as a later option.

### Phase 3 — Transport & identity hardening

- Confirm `UPDATE_MANIFEST_URL` (build-time dart-define, `fasting_app.dart:40`)
  is always `https://`; assert scheme in `UpdateService`.
- Persist the Supabase session in secure storage (verify what
  `supabase_flutter` already does on mobile; document, only change if it
  persists plaintext).
- Optional: TLS certificate pinning for Supabase + AI endpoints.

### Phase 4 — Trust & compliance (mostly out of this repo)

- **Supabase Row-Level Security** — verify/enable RLS on every table
  (`finance_records`, `nutrition_logs`, `activity_logs`, `backups`, …) so the
  anon key can only ever touch the JWT owner's rows. Single most important
  server-side control. (Server-side — tracked here as a checklist item.)
- In-app **"Delete my account & data"** flow (local `clearUserData` exists; add
  the server-side delete + UI).
- **Privacy policy** + data-handling disclosure (store listing requirement for
  health/finance).
- **Data minimization:** drop sensitive absolute amounts from the widget
  snapshot where feasible (expense widget exposes spend on a possibly-unlocked
  home screen).

## 5. Risks & rollback

- **Migration data loss (Phase 1)** — mitigation: per-key, write-before-delete,
  idempotent, device-tested; ship behind a flag with a one-version bake.
- **Native widgets break (Phase 1)** — mitigation: widget keys explicitly
  excluded from encryption; verified by on-device render test.
- **Cloud snapshot unrecoverable (Phase 2)** — mitigation: user-bound key
  escrow, never device-local key; documented recovery flow.
- **Rollback:** Phase 0 is config + isolated service (trivially revertible).
  Phase 1 downgrade requires a decrypt-on-read fallback for one version so a
  rolled-back build can still read pre-encryption and post-encryption values.

## 6. Suggested PR sequencing

1. **PR A (this plan):** spec doc + **Phase 0** (manifest/backup hardening +
   encrypted `backup.json`). Backup-safe, CI-verifiable, mergeable.
2. **PR B:** Phase 1 encrypted store + migration. **Requires device QA sign-off
   before merge** (no Flutter SDK in CI-only env).
3. **PR C:** Phase 2 cloud snapshot E2E (after key-escrow design review).
4. **PR D / tickets:** Phase 3–4 items.
