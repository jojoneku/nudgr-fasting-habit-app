# Antigravity & Agent Operational Guidelines (AGENTS.md)

This document provides operational instructions for AI agents working in this repository. It exists alongside [`CLAUDE.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/CLAUDE.md) and [`.github/copilot-instructions.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/.github/copilot-instructions.md). Rather than duplicating their contents, this file teaches you how to navigate the existing project knowledge and strictly follow the team's Git and PR conventions.

---

## 1. Where to Find Project Context (Don't Guess, Consult First)

Before implementing features or proposing architectural changes, check the following sources:

* **Active Domain Specifications (`docs/`):**
  * Fasting timer loop: [`docs/fasting_loop_spec.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/docs/fasting_loop_spec.md)
  * RPG stats, levels, streaks: [`docs/stats_spec.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/docs/stats_spec.md)
  * AI Coach & quick logging: [`docs/ai_coach_spec.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/docs/ai_coach_spec.md), [`docs/chat_logging_coverage.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/docs/chat_logging_coverage.md)
  * Treasury / Finance specs: [`docs/expense_classification_spec.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/docs/expense_classification_spec.md), [`docs/credit_accounts_spec.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/docs/credit_accounts_spec.md), [`docs/treasury_web_spec.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/docs/treasury_web_spec.md)
  * Security & backup: [`docs/data_security_spec.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/docs/data_security_spec.md)
* **Design System & UI Patterns:**
  * Design tokens reference: [`lib/app_colors.dart`](file:///d:/Personal%20Projects/intermittent_fasting_2/lib/app_colors.dart), [`lib/views/app_theme.dart`](file:///d:/Personal%20Projects/intermittent_fasting_2/lib/views/app_theme.dart)
  * Reusable UI widgets: [`lib/views/widgets/system/system.dart`](file:///d:/Personal%20Projects/intermittent_fasting_2/lib/views/widgets/system/system.dart)
  * UI reference skills: [`.claude/skills/m3-hig/SKILL.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/.claude/skills/m3-hig/SKILL.md), [`.claude/skills/ui-ux-pro-max/SKILL.md`](file:///d:/Personal%20Projects/intermittent_fasting_2/.claude/skills/ui-ux-pro-max/SKILL.md)
* **Historical Plans:**
  * Prior plan records: [`.claude/plans/`](file:///d:/Personal%20Projects/intermittent_fasting_2/.claude/plans/)

---

## 2. Git & GitHub Pull Request Workflow (Critical Nuances)

This project uses **GitHub Flow** with specific automation cascades. Follow these exact steps:

### A. Branching
* Always branch off up-to-date `dev`:
  ```bash
  git checkout dev
  git pull
  git checkout -b <type>/<short-description>
  ```
* Standard prefixes: `feat/`, `fix/`, `chore/`, `refactor/`.

### B. Pre-PR Validation
* **For code changes (`feat:`, `fix:`, `refactor:`):**
  Verify locally before pushing:
  ```bash
  flutter pub get
  dart analyze lib
  flutter test <relevant-tests>
  ```
  `dart analyze lib` must report **0 errors**, and relevant tests must pass.
* **For doc-only changes (`docs:`, markdown, comments):**
  Skip local test suites to save time—GitHub CI will run full checks on the PR anyway.

### C. Conventional Commits & Auto-Semver
Commit messages govern the automated release version bumps:
* `<type>(<scope>): <summary>`
* **Semver rules for CI:**
  * `feat!` or body containing `BREAKING CHANGE:` $\rightarrow$ **Major** bump
  * `feat:` (without `!`) $\rightarrow$ **Minor** bump
  * `fix:`, `perf:`, `refactor:`, `chore:`, `ci:`, `test:`, `docs:` $\rightarrow$ **Patch** bump

### D. Opening the PR
* **Target branch is always `dev`** (never open PRs against `main`):
  ```bash
  git push -u origin HEAD
  gh pr create --base dev --title "<type>(<scope>): <summary>" --body "<markdown summary and test checklist>"
  ```

### E. Merging Strategy (Strict Rule)
* **Check CI first:**
  ```bash
  gh pr checks <PR_NUMBER>
  ```
* **Merge command:**
  ```bash
  gh pr merge <PR_NUMBER> --merge --delete-branch
  ```
  > [!IMPORTANT]
  > **ALWAYS use `--merge` (merge commit). NEVER use `--squash` or `--rebase`.**
  > Every PR into `dev` in this repository preserves individual commit history (`Merge pull request #NNN from jojoneku/...`).

### F. The Release Ripple Effect
> [!WARNING]
> **Merging into `dev` automatically triggers a release!**
> Pushing or merging to `dev` initiates CI, followed by an automatic `Promote dev → main` PR merge. This triggers `Release — Build & Deploy APK` plus Supabase and Lambda cloud deployments. Be confident before merging.

### G. Resolving Merge Conflicts
If `dev` moves ahead while your PR is open:
```bash
git checkout dev && git pull
git checkout <your-branch>
git rebase dev
# Resolve conflicts in conflicting files, stage them with git add, then:
git rebase --continue
git push --force-with-lease
```

---

## 3. Core Architectural Guardrails (MVP)

When writing or reviewing code, uphold these core constraints:

1. **No Logic in Views:**
   * Widgets are purely declarative and dumb.
   * Never place conditional evaluations, filters, or calculations inside `build()`.
   * Bind views to Presenters with `ListenableBuilder` and query `presenter.getter`.
2. **Dual-Theme Compatibility:**
   * Never hardcode `AppColors.*` or `AppColorsLight.*` inside widgets.
   * Consume theme values exclusively via `Theme.of(context)` (e.g. `colorScheme.*`, `scaffoldBackgroundColor`, `textTheme.*`).
   * Add new color tokens to both `AppColors` and `AppColorsLight` in [`lib/app_colors.dart`](file:///d:/Personal%20Projects/intermittent_fasting_2/lib/app_colors.dart).
3. **Single Source of Truth & Dependency Graph:**
   * If a presenter needs data owned by another presenter, it must subscribe as a listener to the owner.
   * Assemble cross-presenter wiring in the graph ([`TreasuryPresenters`](file:///d:/Personal%20Projects/intermittent_fasting_2/lib/presenters/treasury_presenters.dart)), never ad-hoc inside UI shells.
4. **Mobile UX Rules:**
   * Minimum touch target size: $44 \times 44$ logical pixels.
   * Primary action buttons must reside in the bottom 30% of the screen (Thumb Zone).
   * Animations: 150–300 ms micro-interactions, never exceeding 400 ms.
5. **Constructor Injection Only:**
   * Pass dependencies via constructors. Avoid global singletons, service locators (`GetIt`), or hidden global state.
