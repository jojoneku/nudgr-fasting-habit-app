# Deploying the Treasury Web companion (Firebase Hosting)

The web companion (`lib/main_web.dart`) builds to a **static site** — no server.
It talks to the existing Supabase backend from the browser, so hosting just
serves files on a CDN. We use **Firebase Hosting** (free Spark tier).

## How it deploys

`.github/workflows/ci.yml` → job **`deploy_web`** runs on every push to `main`
(after `analyze_format` + `test` pass), when a web-relevant path changed. It:

1. Builds via `scripts/build_web.sh` (not a bare `flutter build web`).
2. Writes a production `.env` from CI secrets with **`WEB_REDIRECT_URL` empty**,
   so Google sign-in returns to the live origin (not `localhost`).
3. Deploys `build/web` to the Firebase Hosting **live** channel.

### No service worker (and why there's still a file at that path)

The companion ships **no** service worker: `scripts/build_web.sh` passes
`--pwa-strategy=none`. Flutter's worker serves the *previous* bundle while it
installs the new one, so new code only activated on the **next** navigation —
every deploy took two loads to appear and read as "the deploy didn't land",
which is exactly how the Treasury redesign looked missing for an hour after it
went live. An authenticated dashboard gains nothing from offline caching.

Dropping the worker is not enough on its own: a browser that already registered
one keeps serving from that registration indefinitely if the script URL starts
404ing. So `scripts/build_web.sh` copies `scripts/web/retire_service_worker.js`
over the 0-byte `flutter_service_worker.js` Flutter still emits. Browsers poll
that path for updates, receive a worker whose only job is to delete its caches,
unregister itself, and reload its tabs, and heal permanently. The script asserts
the copy survived, so a Flutter upgrade that changes this behaviour fails the
build instead of silently shipping a build that can't un-stick anyone.

**Never build the web bundle with a bare `flutter build web`** — you'd ship the
0-byte worker and strand every existing client.

`firebase.json` configures the SPA rewrite (`** → /index.html`) and no-cache
headers for `index.html`, the service-worker path, and the entrypoint scripts
(`flutter_bootstrap.js`, `main.dart.js`, `flutter.js`, `version.json`) so app
code is never served stale. There's intentionally no
committed `.firebaserc` (a placeholder one breaks every CLI command, even
`login`) — run `firebase use --add` locally to generate one; CI uses the
`FIREBASE_PROJECT_ID` secret instead.

## One-time setup (required before it works)

1. **Create a Firebase project** (or reuse one) and enable **Hosting**.
   You get `https://<project>.web.app` and `https://<project>.firebaseapp.com`.
2. **Add GitHub repo secrets** (Settings → Secrets and variables → Actions):
   - `FIREBASE_PROJECT_ID` — the project id.
   - `FIREBASE_SERVICE_ACCOUNT` — a service-account JSON with the *Firebase
     Hosting Admin* role. Easiest: run `firebase init hosting:github` locally
     (it creates the service account + sets this secret for you), or generate
     one in the Google Cloud console and paste the JSON.
   - (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID` already exist.)
3. **Allow the live URL in Supabase** → Auth → URL Configuration → *Redirect
   URLs*: add `https://<project>.web.app` and `https://<project>.firebaseapp.com`
   (and set the Site URL). Without this, Google sign-in fails on the live site.
   Google's OAuth console already has the Supabase callback — no change there.
4. For local deploys, run `firebase use --add` to pick the project (writes a
   local `.firebaserc`).

## Deploy by hand (optional, to validate before CI)

```bash
scripts/build_web.sh
# .env must have WEB_REDIRECT_URL empty (or set to the live URL) for OAuth
npx firebase-tools deploy --only hosting   # or: firebase deploy --only hosting
```

## Notes

- Only **public** values go in the bundled `.env` (Supabase URL + anon key,
  Google web client id). The anon key is meant to be public; RLS protects data.
- Mobile-only plugins never reach the web bundle because the build targets
  `lib/main_web.dart` (its transitive imports only).
