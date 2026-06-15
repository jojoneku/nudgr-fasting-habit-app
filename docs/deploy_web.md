# Deploying the Treasury Web companion (Firebase Hosting)

The web companion (`lib/main_web.dart`) builds to a **static site** — no server.
It talks to the existing Supabase backend from the browser, so hosting just
serves files on a CDN. We use **Firebase Hosting** (free Spark tier).

## How it deploys

`.github/workflows/ci.yml` → job **`deploy_web`** runs on every push to `main`
(after `analyze_format` + `test` pass), when a web-relevant path changed. It:

1. Builds `flutter build web --release -t lib/main_web.dart`.
2. Writes a production `.env` from CI secrets with **`WEB_REDIRECT_URL` empty**,
   so Google sign-in returns to the live origin (not `localhost`).
3. Deploys `build/web` to the Firebase Hosting **live** channel.

`firebase.json` configures the SPA rewrite (`** → /index.html`) and no-cache
headers for `index.html` / the service worker. `.firebaserc` is only used for
local `firebase deploy` — set its project id if you deploy by hand.

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
4. Set `.firebaserc`'s `default` to your project id (for local deploys).

## Deploy by hand (optional, to validate before CI)

```bash
flutter build web --release -t lib/main_web.dart
# .env must have WEB_REDIRECT_URL empty (or set to the live URL) for OAuth
npx firebase-tools deploy --only hosting   # or: firebase deploy --only hosting
```

## Notes

- Only **public** values go in the bundled `.env` (Supabase URL + anon key,
  Google web client id). The anon key is meant to be public; RLS protects data.
- Mobile-only plugins never reach the web bundle because the build targets
  `lib/main_web.dart` (its transitive imports only).
