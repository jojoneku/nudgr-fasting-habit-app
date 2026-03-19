---
name: git-workflow
description: "Use when establishing branching strategies, writing Conventional Commits, creating or reviewing PRs, resolving PR review comments, merging PRs (including CI verification and post-merge cleanup), handling merge conflicts, or managing releases on GitHub."
compatibility: "Requires git, gh CLI."
allowed-tools: Bash(git:*) Bash(gh:*)
---

# Git Workflow Skill

Expert patterns for Git version control: branching, commits, collaboration, and CI/CD.

## Reference Files

| Reference | When to Load |
|-----------|--------------|
| `references/branching-strategies.md` | Managing branches, choosing branching model |
| `references/commit-conventions.md` | Writing commits, semantic versioning |
| `references/pull-request-workflow.md` | Creating/reviewing PRs, merging, conflict resolution |

### Content Triggers

- **PR operations** (create, review, merge, thread resolution, conflicts): load `references/pull-request-workflow.md`
- **Branching strategy**: load `references/branching-strategies.md`
- **Commit messages**: load `references/commit-conventions.md`

---

## This Project's Branch Strategy

**GitHub Flow** — simplified, continuous deployment friendly.

```
main ── always deployable (protected)
dev  ── integration branch (default PR target)
feat/*, fix/*, chore/* ── short-lived feature branches
```

### Branch Naming

```bash
feat/TICKET-description       # New feature
fix/TICKET-bug-description     # Bug fix
chore/description              # Tooling, deps, docs
```

### Typical Flow

```bash
git checkout dev && git pull
git checkout -b feat/fasting-loop-timer

# ... implement + test ...

git push -u origin HEAD
gh pr create --base dev --title "feat: ..."
# After approval:
gh pr merge --squash
git checkout dev && git pull
git branch -d feat/fasting-loop-timer
```

---

## Conventional Commits (Quick Reference)

```
<type>[scope]: <description>

[optional body]

[optional footer]
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

**Types:**

| Type | Semver | When |
|------|--------|------|
| `feat` | MINOR | New feature |
| `fix` | PATCH | Bug fix |
| `refactor` | — | Code restructure, no behavior change |
| `test` | — | Adding/fixing tests |
| `chore` | — | Deps, tooling, CI |
| `docs` | — | Documentation only |
| `perf` | PATCH | Performance improvement |

**Breaking change:** Add `!` after type: `feat!: redesign storage API`

### Examples for This App

```
feat(presenter): add XP calculation on fast completion
fix(notifications): reschedule alarm after app restart
refactor(storage): extract StorageService abstract interface
test(presenter): add streak reset unit tests
chore(deps): upgrade flutter_local_notifications to 18.0
```

---

## PR Workflow

### Creating a PR

```bash
gh pr create \
  --base dev \
  --title "feat(fasting): add timer pause/resume" \
  --body "$(cat <<'EOF'
## Summary
- Added pause/resume to FastingPresenter
- Persists paused state via StorageService
- Timer resumes on app restart

## Test plan
- [ ] Start fast, pause, reopen app — timer stays paused
- [ ] Resume fast — timer continues from paused duration
- [ ] XP awarded correctly on completion after pause

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Merging

```bash
# Check CI passes first
gh pr checks <NUMBER>

# Squash merge (preferred for this project)
gh pr merge <NUMBER> --squash --delete-branch
```

### Post-Merge Cleanup

```bash
git checkout dev && git pull
git remote prune origin
git branch -d feat/my-feature  # if not auto-deleted
```

---

## Conflict Resolution

```bash
git checkout dev && git pull
git checkout feat/my-branch
git rebase dev

# Fix conflicts in each file, then:
git add <file>
git rebase --continue

git push --force-with-lease
```

---

## Common Tasks

```bash
# Check current PR status
gh pr status

# View open PRs
gh pr list

# Check out a PR locally
gh pr checkout <NUMBER>

# View PR diff
gh pr diff <NUMBER>

# Add reviewer
gh pr edit <NUMBER> --add-reviewer username

# Close PR without merging
gh pr close <NUMBER>
```
