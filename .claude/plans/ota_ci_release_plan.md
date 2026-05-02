# OTA CI Release Job — Implementation Plan

## Goal
Add a `release` job to `ci.yml` that fires automatically on every push to `main`, builds a
release APK, generates `manifest.json`, and upserts both files to Supabase Storage. After this
lands, pushing to `dev` (which auto-promotes to `main`) is the entire release workflow — no
USB cable, no manual uploads.

---

## Affected Files

| File | Action |
|---|---|
| `.github/workflows/ci.yml` | Modify — add `release` job after existing jobs |
| GitHub repo secrets | Add `SUPABASE_SERVICE_ROLE_KEY` (manual, one-time) |

No Flutter/Dart changes — this plan is CI-only.

---

## Key Decisions

### Build number strategy
`pubspec.yaml` currently has `version: 1.0.0+2002`. We cannot use bare `GITHUB_RUN_NUMBER`
(probably ~50–200 by now) because it would be lower than 2002 and the installed app would
never see an update.

**Decision:** use `GITHUB_RUN_NUMBER + 2100` as the build number passed to `--build-number`.
- First release CI run → build number ≥ 2101 (safely above current 2002)
- Monotonically increases forever with each push to main
- No manual bumping ever needed

The human-readable **version string** is auto-bumped by CI using the conventional commit type
of the HEAD commit — no manual bumping ever needed for patch/minor. Major requires `!` or
`BREAKING CHANGE` in the commit body (intentionally explicit).

### Manifest generation
Generated inline in bash using `python3 -c` (available on all `ubuntu-latest` runners —
no `jq` install needed):
```bash
python3 -c "
import json, sys
print(json.dumps({
  'version': sys.argv[1],
  'build_number': int(sys.argv[2]),
  'apk_url': sys.argv[3],
  'release_notes': sys.argv[4],
  'released_at': sys.argv[5]
}))" "$VERSION" "$BUILD_NUMBER" "$APK_URL" "$RELEASE_NOTES" "$RELEASED_AT" > manifest.json
```

### Version auto-bump strategy
CI reads the HEAD commit message and applies conventional commit rules:

| Commit signal | Bump | Example |
|---|---|---|
| Subject contains `!` or body has `BREAKING CHANGE` | **major** (`1.0.0 → 2.0.0`) | `feat!: redesign storage API` |
| Type is `feat` (no `!`) | **minor** (`1.0.0 → 1.1.0`) | `feat(quest): add weekly boss` |
| Anything else (`fix`, `chore`, `ci`, `perf`, `refactor`, `test`, `docs`) | **patch** (`1.0.0 → 1.0.1`) | `fix(timer): drift after resume` |

After bumping, CI writes `version: X.Y.Z+<BUILD_NUMBER>` back to `pubspec.yaml` and commits
to `main` with `[skip ci]` in the message — preventing an infinite trigger loop.

### Release notes source
The HEAD commit message on `main` becomes the release notes (first 300 chars).
Extracted via `git log -1 --pretty=%B`. Whatever the dev writes as the commit/merge message
appears in the update prompt.

### Supabase upload mechanism
Plain `curl` against the Supabase Storage REST API. No Supabase CLI install needed.
Upsert via `x-upsert: true` header — same endpoint, same path, every time:
```
POST {SUPABASE_URL}/storage/v1/object/releases/manifest.json   (x-upsert: true)
POST {SUPABASE_URL}/storage/v1/object/releases/app-release.apk (x-upsert: true)
Authorization: Bearer {SUPABASE_SERVICE_ROLE_KEY}
```

### `UPDATE_MANIFEST_URL` dart-define
The manifest URL is `${SUPABASE_URL}/storage/v1/object/public/releases/manifest.json`.
It is constructed from the existing `SUPABASE_URL` secret — no new secret needed for this.
Passed to the Flutter build as `--dart-define=UPDATE_MANIFEST_URL=<url>`.

---

## Implementation Order

### Step 1 — Add GitHub secret (manual, one-time)
- [ ] Go to repo → Settings → Secrets → Actions → New secret
- [ ] Name: `SUPABASE_SERVICE_ROLE_KEY`
- [ ] Value: found in Supabase dashboard → Project Settings → API → `service_role` key
- [ ] **Do not commit this key anywhere**

### Step 2 — Add `release` job to `ci.yml`

Job shape:
```
release:
  name: Release — Build & Deploy APK
  runs-on: ubuntu-latest
  needs: [analyze_format, test]
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  permissions:
    contents: write   # needed to push the version bump commit back to main
```

Steps inside the job:

1. `actions/checkout@v4` with `token: ${{ secrets.GITHUB_TOKEN }}`
   (explicit token required so the subsequent `git push` is authenticated)
2. `actions/setup-java@v4` with `distribution: temurin, java-version: 17`
3. `subosito/flutter-action@v2` (stable, cached)
4. Create `.env` file (same block as other jobs)
5. `flutter pub get`
6. **Compute release metadata** — read current version, parse commit msg, determine bump,
   compute new version string + build number:
   ```bash
   CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)
   # parse MAJOR.MINOR.PATCH
   COMMIT_MSG=$(git log -1 --pretty=%B)
   # detect bump type from commit message
   if echo "$COMMIT_MSG" | grep -qE '(BREAKING CHANGE|!:)'; then BUMP=major
   elif echo "$COMMIT_MSG" | grep -qE '^feat(\(.+\))?:'; then BUMP=minor
   else BUMP=patch; fi
   # apply bump
   NEW_VERSION=<bumped from CURRENT per BUMP>
   BUILD_NUMBER=$((GITHUB_RUN_NUMBER + 2100))
   ```
7. **Bump `pubspec.yaml`**:
   ```bash
   sed -i "s/^version: .*/version: ${NEW_VERSION}+${BUILD_NUMBER}/" pubspec.yaml
   ```
8. **Build APK** with `--build-name=$NEW_VERSION --build-number=$BUILD_NUMBER --dart-define=UPDATE_MANIFEST_URL=...`
9. **Generate `manifest.json`** (python3 inline)
10. **Upload `manifest.json`** via curl (x-upsert: true)
11. **Upload `app-release.apk`** via curl (x-upsert: true)
    - APK path: `build/app/outputs/flutter-apk/app-release.apk`
12. **Commit + push version bump** back to `main`:
    ```bash
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add pubspec.yaml
    git commit -m "chore(release): bump version to ${NEW_VERSION}+${BUILD_NUMBER} [skip ci]"
    git push
    ```
    `[skip ci]` in the message prevents this commit from re-triggering the workflow.

### Step 3 — Supabase bucket setup (manual, one-time, if not done yet)
- [ ] Supabase dashboard → Storage → New bucket → name: `releases`
- [ ] Public: **yes** (allows the app to fetch manifest + APK without auth)
- [ ] No file size limit override needed (default 50 MB is enough; APK is typically 30–50 MB)

---

## Full Job Definition (for reference during implementation)

```yaml
release:
  name: Release — Build & Deploy APK
  runs-on: ubuntu-latest
  needs: [analyze_format, test]
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  permissions:
    contents: write

  steps:
    - uses: actions/checkout@v4
      with:
        token: ${{ secrets.GITHUB_TOKEN }}

    - uses: actions/setup-java@v4
      with:
        distribution: temurin
        java-version: '17'

    - uses: subosito/flutter-action@v2
      with:
        channel: stable
        cache: true

    - name: Create .env
      run: |
        echo "SUPABASE_URL=${{ secrets.SUPABASE_URL }}" >> .env
        echo "SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}" >> .env
        echo "GOOGLE_WEB_CLIENT_ID=${{ secrets.GOOGLE_WEB_CLIENT_ID }}" >> .env

    - name: Install dependencies
      run: flutter pub get

    - name: Compute release metadata
      id: meta
      run: |
        # Current version string (strip build number)
        CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)
        MAJOR=$(echo $CURRENT | cut -d. -f1)
        MINOR=$(echo $CURRENT | cut -d. -f2)
        PATCH=$(echo $CURRENT | cut -d. -f3)

        # Determine bump type from HEAD commit message
        COMMIT_MSG=$(git log -1 --pretty=%B)
        if echo "$COMMIT_MSG" | grep -qE '(BREAKING CHANGE|!:)'; then
          MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0
        elif echo "$COMMIT_MSG" | grep -qP '^feat(\(.+\))?:'; then
          MINOR=$((MINOR + 1)); PATCH=0
        else
          PATCH=$((PATCH + 1))
        fi

        NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
        BUILD_NUMBER=$((GITHUB_RUN_NUMBER + 2100))
        APK_URL="${{ secrets.SUPABASE_URL }}/storage/v1/object/public/releases/app-release.apk"
        MANIFEST_URL="${{ secrets.SUPABASE_URL }}/storage/v1/object/public/releases/manifest.json"
        RELEASED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT
        echo "build_number=$BUILD_NUMBER" >> $GITHUB_OUTPUT
        echo "apk_url=$APK_URL" >> $GITHUB_OUTPUT
        echo "manifest_url=$MANIFEST_URL" >> $GITHUB_OUTPUT
        echo "released_at=$RELEASED_AT" >> $GITHUB_OUTPUT
        printf 'release_notes<<EOF\n%s\nEOF\n' "$(echo "$COMMIT_MSG" | head -c 300)" >> $GITHUB_OUTPUT

    - name: Bump pubspec version
      run: |
        sed -i "s/^version: .*/version: ${{ steps.meta.outputs.new_version }}+${{ steps.meta.outputs.build_number }}/" pubspec.yaml

    - name: Build APK
      run: |
        flutter build apk --release \
          --build-number=${{ steps.meta.outputs.build_number }} \
          --build-name=${{ steps.meta.outputs.new_version }} \
          --dart-define=UPDATE_MANIFEST_URL=${{ steps.meta.outputs.manifest_url }}

    - name: Generate manifest.json
      run: |
        python3 -c "
        import json, sys
        print(json.dumps({
          'version': sys.argv[1],
          'build_number': int(sys.argv[2]),
          'apk_url': sys.argv[3],
          'release_notes': sys.argv[4],
          'released_at': sys.argv[5]
        }, indent=2))
        " \
          "${{ steps.meta.outputs.new_version }}" \
          "${{ steps.meta.outputs.build_number }}" \
          "${{ steps.meta.outputs.apk_url }}" \
          "${{ steps.meta.outputs.release_notes }}" \
          "${{ steps.meta.outputs.released_at }}" > manifest.json
        cat manifest.json

    - name: Upload manifest to Supabase
      run: |
        curl -sf -X POST \
          "${{ secrets.SUPABASE_URL }}/storage/v1/object/releases/manifest.json" \
          -H "Authorization: Bearer ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}" \
          -H "Content-Type: application/json" \
          -H "x-upsert: true" \
          --data-binary @manifest.json

    - name: Upload APK to Supabase
      run: |
        curl -sf -X POST \
          "${{ secrets.SUPABASE_URL }}/storage/v1/object/releases/app-release.apk" \
          -H "Authorization: Bearer ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}" \
          -H "Content-Type: application/vnd.android.package-archive" \
          -H "x-upsert: true" \
          --data-binary @build/app/outputs/flutter-apk/app-release.apk

    - name: Commit version bump
      run: |
        git config user.name "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git add pubspec.yaml
        git commit -m "chore(release): bump version to ${{ steps.meta.outputs.new_version }}+${{ steps.meta.outputs.build_number }} [skip ci]"
        git push
```

---

## RPG Impact
None — CI infrastructure only.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Version bump commit re-triggers the `release` job (infinite loop) | `[skip ci]` in the commit message tells GitHub Actions to skip all workflows for that push. |
| `GITHUB_RUN_NUMBER + 2100` collides with a future pubspec build number | After this lands, CI owns the build number — the pubspec `+XXXX` is always overwritten. No manual edits to the `+` part ever needed. |
| APK > 50 MB hits Supabase free tier storage limit | Free tier is 1 GB total storage. Even at 80 MB per APK (upserted, so only 1 copy), well within limits. |
| `curl -sf` fails silently | `-f` causes curl to exit non-zero on HTTP errors (4xx/5xx), which fails the CI step. Error logged to CI. |
| Multiline release notes break JSON generation | `head -c 300` caps notes at 300 chars; `json.dumps` in Python handles escaping correctly. |
| `release` job runs on PRs to main (not just pushes) | `if: github.event_name == 'push'` guard already filters this out. PRs only trigger analyze+test. |
| Service role key exposed in logs | `curl` command uses `${{ secrets.* }}` — GitHub Actions automatically masks secret values in logs. |
| First-ever upload: bucket doesn't exist yet | Step 3 (manual bucket creation) must be done before the first push to main that triggers release. |

---

## Acceptance Criteria
- [ ] Pushing to `main` (or merging dev → main via auto-merge) triggers the `release` job
- [ ] `release` job only runs after both `analyze_format` and `test` pass
- [ ] `fix:` commit on main → patch bump (`1.0.0 → 1.0.1`); `feat:` → minor; `feat!:` → major
- [ ] APK is built with `--build-number` = `GITHUB_RUN_NUMBER + 2100`
- [ ] `manifest.json` contains correct `version`, `build_number`, `apk_url`, `released_at`
- [ ] `pubspec.yaml` is updated to `version: X.Y.Z+<build>` and committed back to `main` with `[skip ci]`
- [ ] The version bump commit does not trigger a second `release` job run
- [ ] Both files appear in Supabase `releases` bucket; previous versions are overwritten
- [ ] Bucket stays at exactly 2 files after multiple releases
- [ ] PRs to main do **not** trigger the release job
- [ ] CI step fails visibly (non-zero exit) if Supabase upload returns an error

---
*Awaiting approval before any code is written.*
