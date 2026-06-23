# Shorebird Code Push (OTA updates)

We ship most updates as **Shorebird code-push patches** — small over-the-air
updates that change only the Dart code, so users get fixes on the next launch
**without re-downloading the whole APK**. The existing APK + `manifest.json`
flow (see `UpdateService`) is kept for the changes Shorebird *can't* patch.

## When to patch vs. cut a full release

| Change | How to ship |
|---|---|
| Dart code — logic, RPG math, UI, bug fixes | **`shorebird patch`** (instant OTA) |
| Assets bundled in the patch (images, fonts) | **`shorebird patch`** |
| Native Kotlin/Swift, `AndroidManifest`, permissions, app icon | **Full APK release** |
| Adding/upgrading a plugin with native code | **Full APK release** |
| Bumping the Flutter/Dart SDK version | **Full APK release** |
| `version` / `buildNumber` change | **Full APK release** |

A patch only applies to the `shorebird release` it was built against. After any
"full APK release" row above, cut a **new** `shorebird release` and distribute
that APK through the normal `manifest.json` flow; then patch onto it.

## One-time setup

1. `shorebird init` in the repo root → registers the app and writes the real
   `app_id` into `shorebird.yaml` (currently a placeholder).
2. Shorebird console → Account → API Keys → create a CI token.
3. Add it to GitHub repo secrets as `SHOREBIRD_TOKEN`.

## Day-to-day

Locally:

```bash
shorebird release android   # baseline — distribute via the APK manifest, once
shorebird patch android     # every Dart-only change after → instant OTA
```

Or via CI: run the **Shorebird** workflow (`.github/workflows/shorebird-patch.yml`)
manually and pick `mode: patch` (or `release`). It's a separate, manual-only
workflow so it never interferes with the APK pipeline in `ci.yml`.

## In-app behaviour

- `shorebird.yaml` has `auto_update` on, so the engine downloads and applies
  patches silently on the next launch — no code required.
- `PatchUpdateService` + `UpdatePresenter.checkForPatch()` additionally observe
  when a patch has been staged and surface a non-blocking "Update installed —
  reopen Nudgr to apply" banner (`UpdatePrompt`). It's a no-op in debug, on web,
  and in plain (non-`shorebird release`) builds.
