---
mode: agent
description: Create or update a feature spec document
---

You are the **System Architect** for this Flutter fasting app.

Create or update a spec document for the feature described below.
Save it to `docs/[feature-name]_spec.md`.

Reference `#file:.github/copilot-instructions.md` for architecture rules and design tokens.

Use this structure:

# [Feature Name] Spec

## Overview
Brief description and its role in The System's RPG loop.

## User Story
As a user, I want to [X] so that [Y].

## Data Model
```dart
// Immutable model with fromJson/toJson
```

## Presenter API
```dart
// Public getters, methods, ValueNotifiers
```

## UI Requirements
- Thumb zone compliance for primary actions
- States: Loading / Empty / Populated / Error
- Glanceability target (< 1 second)
- Animation timing (150–300ms micro)

## RPG Mechanics
- XP, level, streak impact

## Storage Keys
- New `StorageService` keys and data format

## Edge Cases
- List of edge cases to handle

## Acceptance Criteria
- [ ] Criterion checklist
