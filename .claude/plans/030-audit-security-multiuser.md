# Plan 030 — Audit: Security & Multi-User Readiness

> **Status:** Audit findings + remediation plan. Generated from a full-repo architectural review.
> **Severity of domain:** 🔴 **HIGHEST.** This is the blocker for letting anyone besides the owner use the app.
> **One-sentence summary:** The app is single-namespace and single-trust today; the moment a second user signs in — on a shared device *or* a fresh one — local data bleeds into the wrong cloud account, and the cloud AI endpoint is (very likely) open to the internet for anyone to run up an AWS bill.

---

## Why this exists

The owner plans to onboard other users. The codebase was built single-user and several assumptions only hold for a single trusted account on a single device. These must be fixed **before** any second user exists, because some of the failures corrupt cloud data irreversibly.

---

## Findings

### 🔴 C1 — Sign-out clears no local data → next user inherits the previous user's entire dataset
- **Where:** `lib/presenters/auth_presenter.dart:95-99`, `lib/views/home_screen.dart:209-217` (`_tearDownSync`), `lib/views/settings_screen.dart:159`.
- **Problem:** `signOut()` only nulls callbacks and disposes the sync service. No SharedPreferences are cleared. The sign-out dialog even reassures "Your local data stays safe on this device."
- **Impact (first time User B signs in on User A's device):** App boots User A's data into all presenters (the app is usable signed-out — "Log in later", `home_screen.dart:152-156`). When User B signs in, `pushAll()` is gated per-user-per-device (`sync_initial_push_done_v2_$userId`, `sync_service.dart:695`), so for new User B it runs and **uploads User A's still-resident local fasting history, finances, body measurements, and chat into User B's cloud rows.** The leftover global `syncQueue` also flushes User A's pending writes into User B's account.
- **Fix:** On sign-out, wipe all synced-domain keys + `syncQueue` + `syncTimestamps` + `sync_initial_push_done_v2_*`, and clear the in-memory `SyncQueue` (`_queue.clear()`, `_timestamps.clear()` — clearing prefs alone won't reset the session-cached copy). Update the misleading dialog copy.

### 🔴 C2 — SharedPreferences keys are global, not per-user → guaranteed data mixing on shared devices
- **Where:** `lib/services/storage_service.dart:29-74` — every key is a bare constant (`'userStats'`, `'finance_accounts'`, `'history'`, …).
- **Problem:** One namespace for all accounts. Sign-in does not segregate storage. Pre-auth local data ("Log in later") is later pushed into whatever account signs in.
- **Fix (preferred, also fixes C1 for free):** Prefix every key with the signed-in user id (`u/$userId/userStats`). On sign-in, if the namespace doesn't match the authenticated user, start clean. This is the robust multi-user foundation.

### 🔴 C3 — Two synced tables (`fasting_state`, `user_quests`) are missing from the migration / RLS
- **Where:** client pushes/pulls them at `sync_service.dart:186` and `:205`; `docs/supabase_migration.sql` defines only `user_profile`, `user_collections`, `nutrition_logs`, `activity_logs`, `finance_records`.
- **Problem:** Either the tables don't exist (sync silently stalls — the push loop `break`s on first error, `sync_service.dart:99`) **or** they were created in the dashboard without RLS. If the latter, **any authenticated user can read/write every user's fasting history and quests with only the public anon key.** This is exactly the "anon key is safe only if RLS is correct" trap — unverified for 2 of 7 tables.
- **Fix:** Add both tables to the migration with the same `user_owns_row` RLS + grants. **Audit the live Supabase project and confirm RLS is ENABLED on every table.** Treat "table used by client but absent from migration" as a standing red flag.

### 🔴 C4 (backend) — Cloud AI endpoint has no authentication and no rate limiting
- **Where:** `backend/ai-coach/lambda_function.py:12-34` (byte-identical to deployed `lambda.zip`); claimed-but-absent in `.claude/plans/024-cloud-ai-food-logging.md`.
- **Problem:** The Lambda reads `op`/`payload` and calls Bedrock directly. There is **zero** JWT verification despite the client sending `Authorization: Bearer <Supabase JWT>` and `cloud_ai_coach_service.dart:23-24` falsely claiming "The Lambda's JWT authorizer rejects calls without a valid Bearer token." The IaC mismatch (Plan 034 SEV-1) strongly implies the live API Gateway authorizer is NONE.
- **Impact:** Anyone who learns the URL can invoke Bedrock Claude Haiku on the owner's AWS account, unlimited — **direct, unbounded, adversary-controlled billing exposure**, plus it processes prompts containing user PII.
- **Fix:** Verify the Supabase JWT in-Lambda (signature against Supabase JWKS, check `aud`/`exp`) **or** put a real API Gateway JWT authorizer in front (issuer = Supabase). Add a per-user daily cap (DynamoDB counter keyed on `sub`). Bound input length. Return 401/429. *(Cross-referenced in Plan 034; lives here too because it's the top security risk.)*

### 🟠 H1 — Full JWT printed to logs on every sign-in and token refresh
- **Where:** `auth_presenter.dart:40-52` and `:69-83`.
- **Problem:** The full access token is `debugPrint`ed in 800-char chunks (guarded by `kDebugMode`). In debug/profile builds the bearer token lands in device logs (logcat/Console), readable via cable or log-collection tooling.
- **Fix:** Remove both JWT-dump blocks. If needed for backend testing, gate behind an explicit opt-in flag and never log the whole token.

### 🟠 H2 — HuggingFace token handed in plaintext to every authenticated user, cached forever
- **Where:** `supabase/functions/get-hf-token/index.ts:49-54`, `lib/services/remote_secrets_service.dart:17-53`.
- **Problem:** The Edge Function (correctly JWT-gated) returns the raw org `HF_TOKEN`; the client caches it in `SharedPreferences` indefinitely. Any signed-up user can read it; on a rooted device it's trivially extractable. No rotation path — revoking it silently breaks downloads, and cached copies survive revocation.
- **Fix:** Scope the HF token read-only to the single model repo (low blast radius), store the client cache in `flutter_secure_storage`, document a rotation procedure, and ideally proxy the model download behind a short-lived signed URL instead of dispensing the token at all.

### 🟠 H3 — Sync lifecycle not driven by auth state; account swap without restart binds sync to the wrong user
- **Where:** `auth_presenter.dart:38-56` (stream listener only `notifyListeners`), `home_screen.dart:130-134, 187-207` (`_initSync` early-returns if `_syncService != null`).
- **Problem:** Sync init/teardown only fires on the explicit `onFirstSignIn` callback and the startup check — not on `AuthChangeEvent.signedIn/signedOut`. A session swap or re-emitted `signedIn` can leave `SyncService._userId` stale, and the early-return blocks rebinding.
- **Fix:** Drive `_initSync`/`_tearDownSync` off the auth stream events (compare userId), and assert `_syncService._userId == _auth.currentUserId` before any push.

### 🟡 M1 — `exportAllData`/`importAllData` dump and overwrite the whole prefs store, unscoped
- **Where:** `local_storage_service.dart:1159-1167` (export), `:1234-1259` (import does `prefs.clear()` then bulk-restore).
- **Problem:** Export serializes every key (incl. sync-control keys); import wipes and restores blindly with no user validation. With global keys (C2), importing User A's backup under User B injects A's data into B on next sync.
- **Fix:** Scope export/import to the current user's namespace; exclude sync-control keys; validate `user_id` on import.

### 🟡 M2 — PII/health/financial data stored unencrypted at rest
- **Where:** throughout `local_storage_service.dart` — body measurements, weight, TDEE profile (age/sex/height/weight), full finance ledger, nutrition + chat — all plaintext JSON in SharedPreferences.
- **Fix:** Move the sensitive subset to `flutter_secure_storage` or an encrypted store (SQLCipher); disable Android auto-backup for those keys.

### 🟢 L1 — Secrets-in-bundle assessment (mostly OK)
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID` shipping in the bundle is **expected and safe** — the anon key is `role:anon` and harmless **iff RLS holds on every table.** `.env` is correctly gitignored (`*.env`). No `service_role` key is present. The only real caveat is C3 — the safety guarantee depends on RLS coverage that is currently unverified for 2 tables.

---

## Remediation order

1. **C1 + C2 together** (per-user key namespacing + clear-on-switch) — single root fix; stops the data-bleed that triggers on the first second sign-in.
2. **C3** — add `fasting_state`/`user_quests` to the migration with RLS; **audit live RLS on all tables.**
3. **C4** — lock the cloud endpoint (JWT verify + per-user daily cap). *(Coordinate with Plan 034.)*
4. **H1** (strip JWT logging), **H2** (HF token hardening), **H3** (auth-driven sync lifecycle).
5. **M1, M2, L1** — hardening.

## Definition of done
- A second account signing in on a device that already holds data starts clean and cannot push the prior user's records.
- Every Supabase table has RLS enabled and a `user_owns_row` policy, verified in the live project.
- The cloud endpoint rejects unauthenticated calls and enforces a per-user daily cap.
- No token is ever written to logs; the HF token is in secure storage with a rotation runbook.
