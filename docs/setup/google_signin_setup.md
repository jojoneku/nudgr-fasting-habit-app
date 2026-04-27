# Google Sign-In + Supabase Setup

Complete this once before testing authentication. Takes ~20 minutes.

---

## 1. Create a Supabase Project

1. Go to [supabase.com](https://supabase.com) → New Project
2. Note your **Project URL** and **anon/public API key** from  
   Settings → API

---

## 2. Enable Google Provider in Supabase

1. Supabase dashboard → Authentication → Providers → Google → Enable
2. Leave **Client ID** and **Client Secret** blank for now (filled in step 4)

---

## 3. Google Cloud Console

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a project (or use existing)
3. Enable **Google Sign-In API**: APIs & Services → Enable APIs → search "Google Sign-In"
4. Go to **Credentials** → Create Credentials → OAuth 2.0 Client IDs

### Create the Web Client ID (required by Supabase)
- Application type: **Web application**
- Authorised redirect URIs: add your Supabase callback URL:  
  `https://<your-project-ref>.supabase.co/auth/v1/callback`
- Copy the **Client ID** and **Client Secret** → paste into Supabase Google provider settings (step 2)

### Create the Android Client ID
- Application type: **Android**
- Package name: `com.nudgr.app`
- SHA-1 certificate fingerprint: see step 4 below

---

## 4. Get the SHA-1 Fingerprint

### Debug keystore (for development)
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```
Copy the **SHA-1** value and paste it into the Android OAuth client above.

### Release keystore (for production — when you have a release key)
```bash
keytool -list -v -keystore <path-to-release.keystore> -alias <your-alias>
```

---

## 5. Download `google-services.json`

1. Google Cloud Console → Credentials → Download `google-services.json`
2. Place it at: `android/app/google-services.json`

---

## 6. Enable google-services Gradle Plugin

In `android/settings.gradle.kts`, add to the `plugins` block:
```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

In `android/app/build.gradle.kts`, add to the `plugins` block:
```kotlin
id("com.google.gms.google-services")
```

---

## 7. Fill in the Secrets

Edit `.env` in the project root (already gitignored — never commit this file):
```env
SUPABASE_URL=https://<your-ref>.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
GOOGLE_WEB_CLIENT_ID=<your-web-client-id>.apps.googleusercontent.com
```

---

## 8. Smoke Test

1. `flutter run` on a **real device** (Google Sign-In won't work on most emulators)
2. Settings → Cloud Sync → tap "Continue with Google"
3. Complete OAuth flow
4. Settings should show your email with a green checkmark
5. Kill app → relaunch → Settings should still show signed-in state (session restored)
