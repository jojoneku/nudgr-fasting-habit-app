---
name: github-pr-review
description: Use when reviewing GitHub pull requests with gh CLI - creates pending reviews with code suggestions, batches comments, and chooses appropriate event types (COMMENT/APPROVE/REQUEST_CHANGES)
allowed-tools: AskUserQuestion
---

# GitHub PR Review

## Overview

Workflow for reviewing GitHub pull requests using `gh api` to create pending reviews with code suggestions. **Always use pending reviews to batch comments, even under time pressure.**

**CRITICAL: Always get explicit user approval before posting any review comments.** Show exactly what will be posted and ask for yes/no confirmation using AskUserQuestion.

## When to Use

- Reviewing pull requests
- Adding code suggestions to PRs
- Posting review comments with the gh CLI

## Prerequisites

Check gh CLI is installed before starting:

```bash
gh --version
```

If not installed:
```bash
# Windows
winget install GitHub.cli
# Then authenticate:
gh auth login
```

## Core Workflow

**REQUIRED STEPS (do not skip):**

1. **Check gh CLI is installed** — `gh --version`
2. **Draft the review** — Analyze PR and prepare all comments
3. **Show user exactly what will be posted** — Use AskUserQuestion with yes/no
4. **Get explicit approval** — Wait for user confirmation
5. **Post the review** — Only after approval

### Technical Pattern — Always Use Pending Reviews

```bash
# Step 1: Create PENDING review (no event field)
gh api repos/:owner/:repo/pulls/<PR_NUMBER>/reviews \
  -X POST \
  -f commit_id="<COMMIT_SHA>" \
  -f 'comments[][path]=path/to/file.dart' \
  -F 'comments[][line]=<LINE_NUMBER>' \
  -f 'comments[][side]=RIGHT' \
  -f 'comments[][body]=Comment text

\`\`\`suggestion
// suggested code here
\`\`\`

Additional explanation...' \
  --jq '{id, state}'

# Step 2: Submit the pending review
gh api repos/:owner/:repo/pulls/<PR_NUMBER>/reviews/<REVIEW_ID>/events \
  -X POST \
  -f event="COMMENT" \
  -f body="Optional overall review message"
```

### Getting Prerequisites

```bash
# Get commit SHA
gh pr view <PR_NUMBER> --json commits --jq '.commits[-1].oid'

# Repo owner/name
gh repo view --json owner,name
```

## Event Types

| Event Type | When to Use |
|------------|-------------|
| `APPROVE` | Non-blocking suggestions, PR ready to merge |
| `REQUEST_CHANGES` | Security issues, bugs, architecture violations |
| `COMMENT` | Neutral feedback, questions, clarifications |

## Required Parameters

- `commit_id` — Latest commit SHA
- `comments[][path]` — File path relative to repo root
- `comments[][line]` — End line number (use `-F` for numbers)
- `comments[][side]` — `RIGHT` for added/modified lines, `LEFT` for deleted
- `comments[][body]` — Comment text with optional suggestion block

## Syntax Rules

✅ **DO:**
- Single quotes around `'comments[][path]'` parameters
- `-f` for strings, `-F` for numeric values (line numbers)
- Triple backticks with `suggestion` identifier for code suggestions

❌ **DON'T:**
- Double quotes around `comments[][]` params
- Mix up `-f` and `-F` flags
- Forget to get commit SHA first

## Red Flags — Stop If You Think:

- "User already approved the idea, so I'll skip the approval step"
- "Only one comment, no need for pending review"
- "Time pressure means post immediately"
- "I'll post it and then tell them what I posted"

**All of these mean: STOP. Get explicit approval, then use pending review.**

## This Project's Review Priorities

When reviewing PRs for this Flutter fasting app, check in this order:

1. **Architecture** — No logic in `build()`, no raw hex colors, constructor injection only
2. **Presenter** — RPG math only in Presenters, no calculations in Views
3. **Storage** — All persistence through `StorageService` abstract interface
4. **UX** — Touch targets ≥ 44×44px, animations 150–300ms, primary actions in bottom 30%
5. **Tests** — New features should have presenter unit tests
