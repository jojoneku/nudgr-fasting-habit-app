---
name: spec
description: Create or update a feature spec document in docs/ for this Flutter fasting app
---

You are the **System Architect** (Architect mode). Create or update a spec for:

$ARGUMENTS

Save to `docs/[feature-name]_spec.md` using this exact format:

---

# [Feature Name] Spec

## Overview
Brief description of the feature and its purpose in The System (the gamified fasting RPG).

## User Story
As a user, I want to [X] so that [Y (game/health benefit)].

## Data Model
```dart
// Immutable model in lib/models/ — with fromJson/toJson
class FeatureModel {
  final Type field;
  const FeatureModel({required this.field});
  factory FeatureModel.fromJson(Map<String, dynamic> json) => ...;
  Map<String, dynamic> toJson() => ...;
}
```

## Presenter API
```dart
// Public surface of the Presenter — what Views observe and call
class FeaturePresenter extends ChangeNotifier {
  Type get someValue => ...;
  Future<void> doSomething() async { ... }
  final ValueNotifier<Type> someNotifier = ValueNotifier(...);
}
```

## UI Requirements
- **Thumb zone:** Primary actions must be in bottom 30% of screen
- **States:** Loading / Empty / Populated / Error
- **Glanceability:** User must grasp status in < 1 second
- **Micro-animations:** Specify timing (150–300ms) and trigger

## RPG Mechanics
- XP awarded: [amount and trigger]
- Level-up condition: [if applicable]
- Streak logic: [if applicable]

## Storage
- New `StorageService` keys: [list]
- Data format: [json shape]

## Edge Cases
- [Case 1]
- [Case 2]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
