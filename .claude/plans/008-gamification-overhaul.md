# Plan 008 — Gamification Overhaul: Modular Profile System

**Status:** DRAFT — awaiting approval
**Author:** System Architect
**Date:** 2026-03-20
**Depends on:** Plan 001 (Nav Hub), Plan 005 (Quest Overhaul)

---

## Goal

Right now the player profile is a static character sheet — it shows level, rank, HP, XP, and 5 attributes. It doesn't grow in complexity as the app gains new modules (Calories, Activity, Finance, etc.).

This plan builds a **modular gamification backbone**: a shared event bus and achievement registry that every module (current and future) can plug into. The profile page becomes a living dashboard — it surfaces what each module has contributed to the player's growth, shows earned achievements, unlocked titles, and makes the RPG identity feel truly earned across the whole app.

---

## The Three Problems This Solves

| Problem | Current State | After This Plan |
|---|---|---|
| Modules are siloed | Fasting XP and Quest XP both call `statsPresenter.addXp()` directly | All XP flows through `GamificationService` with a source tag, enabling per-module breakdowns |
| No achievement layer | There is no achievement system | A typed `Achievement` model + registry that any module populates |
| Profile doesn't scale | `StatsView` is hardcoded for fasting + quests data | Profile pulls from a `ProfilePresenter` that aggregates all module signals |

---

## Architecture Overview

```
Module Presenter            GamificationService         StatsPresenter
(FastingPresenter,   ──►   fireEvent(GamEvent)   ──►   addXp()
 QuestPresenter,           registerAchievement()        unlockTitle()
 CaloriesPresenter…)       unlockAchievement()          awardAchievement()
                                │
                                ▼
                         AchievementRegistry      ProfilePresenter
                         (static catalog)    ──►  (aggregates signals
                                                   for ProfileView)
```

Each new module only needs to:
1. Inject `GamificationService` (constructor injection)
2. Call `gamService.fireEvent(...)` when something noteworthy happens
3. Declare its achievements in the `AchievementRegistry`

Zero changes needed to `StatsPresenter` or `ProfileView` to add a new module.

---

## System 1 — GamificationService

New service that decouples modules from `StatsPresenter`.

```dart
// lib/services/gamification_service.dart

enum GamSource { fasting, quests, calories, activity, finance }

class GamEvent {
  final GamSource source;
  final int xp;
  final String? statKey;        // 'str' | 'vit' | 'agi' | 'intl' | 'sen'
  final String? achievementId;  // null = no achievement
  final String? titleId;        // null = no title unlock

  const GamEvent({
    required this.source,
    required this.xp,
    this.statKey,
    this.achievementId,
    this.titleId,
  });
}

abstract class GamificationService {
  Future<void> fireEvent(GamEvent event);
  // Internally: calls statsPresenter.addXp(), records module contribution,
  // unlocks achievement/title if ids provided
}
```

**Module → stat default mapping** (baked into `GamificationService`):

| Module | Primary Stat |
|---|---|
| Fasting | VIT (discipline = vitality) |
| Quests | Varies (uses `Quest.linkedStat`) |
| Calories | STR (fueling = strength) |
| Activity | AGI (movement = agility) |
| Finance | INT (planning = intelligence) |

---

## System 2 — Achievement Model + Registry

```dart
// lib/models/achievement.dart

enum AchievementRarity { common, rare, epic, legendary }

class Achievement {
  final String id;
  final String title;
  final String description;
  final String iconName;          // maps to asset name
  final AchievementRarity rarity;
  final GamSource module;
  final int xpReward;
  DateTime? unlockedAt;           // null = locked

  bool get isUnlocked => unlockedAt != null;
  // fromJson / toJson
}
```

```dart
// lib/services/achievement_registry.dart

// Static catalog — each module declares its achievements here.
// No module needs to edit any other file.
class AchievementRegistry {
  static const List<Achievement> all = [
    // --- Fasting ---
    Achievement(id: 'first_fast',          module: GamSource.fasting, rarity: common,    title: 'First Blood',         description: 'Complete your first fast'),
    Achievement(id: 'shadow_streak_7',     module: GamSource.fasting, rarity: rare,      title: 'Week of Silence',     description: '7-day fasting streak'),
    Achievement(id: 'shadow_streak_30',    module: GamSource.fasting, rarity: epic,      title: 'Shadow Discipline',   description: '30-day fasting streak'),
    Achievement(id: 'omad_warrior',        module: GamSource.fasting, rarity: epic,      title: 'OMAD Warrior',        description: 'Complete 10 OMAD fasts'),
    Achievement(id: 'gate_opener',         module: GamSource.fasting, rarity: legendary, title: 'Gate Opener',         description: 'Reach S-Rank'),
    // --- Quests ---
    Achievement(id: 'quest_7',             module: GamSource.quests,  rarity: common,    title: 'Daily Ritual',        description: 'Complete a quest 7 days in a row'),
    Achievement(id: 'quest_100',           module: GamSource.quests,  rarity: legendary, title: 'Hundred Days',        description: 'Complete any quest 100 times'),
    // --- Future modules register here ---
  ];

  static Achievement? find(String id) =>
      all.where((a) => a.id == id).firstOrNull;
}
```

---

## System 3 — Enhanced UserStats

Add to `lib/models/user_stats.dart`:

```dart
class UserStats {
  // ... existing fields ...

  // NEW
  final List<String> unlockedAchievementIds;   // ordered by unlock time
  final List<String> unlockedTitleIds;          // e.g. 'shadow_monarch', 'omad_warrior'
  final String? activeTitle;                    // player-chosen display title
  final Map<String, int> moduleXpContributions; // { 'fasting': 1200, 'quests': 300 }
}
```

`UserStats.initial()` defaults:
- `unlockedAchievementIds: []`
- `unlockedTitleIds: []`
- `activeTitle: null`
- `moduleXpContributions: {}`

---

## System 4 — ProfilePresenter

New presenter that `ProfileView` listens to. `StatsPresenter` remains the source of truth for XP/level math; `ProfilePresenter` is a read-aggregator.

```dart
// lib/presenters/profile_presenter.dart

class ProfilePresenter extends ChangeNotifier {
  final StatsPresenter _stats;
  final FastingPresenter _fasting;  // for fasting streak, last fast duration
  // Future: inject QuestPresenter, CaloriesPresenter, etc.

  // Getters the view uses:
  List<Achievement> get earnedAchievements; // from registry, filtered by ids in stats
  List<Achievement> get recentAchievements; // last 3 unlocked
  String get displayTitle;                  // activeTitle ?? jobTitle
  List<TitleOption> get availableTitles;    // all unlocked titles
  Map<GamSource, int> get xpByModule;       // pie/bar chart data
  int get fastingStreakDays;
  double get fastingStreakProgress;         // toward next milestone
  // Per-module "activity ring" data for each registered module
  List<ModuleActivitySummary> get moduleActivity;
}

class ModuleActivitySummary {
  final GamSource source;
  final String label;       // "Fasting", "Quests", etc.
  final double progress;    // 0.0–1.0 toward weekly goal
  final String statusLine;  // "16h streak", "3/5 quests today"
}
```

---

## System 5 — ProfileView (StatsView replacement)

The current `StatsView` becomes `ProfileView`. It is restructured into scrollable sections:

### Section A — Identity Header
- Player NAME (editable) + ACTIVE TITLE below name
- RANK badge (gold) | LEVEL | JOB TITLE
- Tap title → title selector bottom sheet (shows all unlocked titles)

### Section B — Vitals
- HP bar (red) + XP bar (cyan) — unchanged from current
- Stat radar chart — unchanged

### Section C — Attribute Panel
- STR / VIT / AGI / INT / SEN allocation — unchanged
- Stat points counter

### Section D — Module Activity Rings *(new)*
- Horizontal scroll row of `ModuleCard` widgets (one per active module)
- Shows: module icon, current streak or today's progress, small progress ring
- Tapping a card navigates to that module's home screen (via Hub nav)
- Locked modules show padlock, greyed out

### Section E — Achievements Gallery *(new)*
- "ACHIEVEMENTS" section header with count badge (X / total)
- Horizontal scroll row of achievement badges
- Common = grey border, Rare = cyan glow, Epic = purple glow, Legendary = gold glow + pulse animation
- Locked = dim silhouette with "???" title
- Tap → achievement detail bottom sheet (title, description, rarity, unlock date, XP reward)
- "VIEW ALL" button → full achievement list screen, filterable by module + rarity

### Section F — XP Breakdown *(new)*
- "POWER SOURCES" header
- Simple horizontal stacked bar: each module's xpContribution in its module color
  - Fasting = cyan, Quests = purple, Calories = green, Activity = orange, Finance = gold
- Shows total XP + percentage per module

---

## Title System

Titles are strings unlocked via achievement or milestone. Player can equip any unlocked title.

**Built-in titles (always available):**
- "Hunter" (default, level 1)

**Achievement-gated titles:**
| Trigger | Title |
|---|---|
| Reach level 10 | "Fasting Novice" |
| Reach level 30 | "Shadow Faster" |
| Reach level 50 (S-Rank) | "Shadow Monarch" |
| Complete `shadow_streak_30` | "Iron Will" |
| Complete `omad_warrior` | "OMAD Warrior" |
| Complete `quest_100` | "Centurion" |

New module = new titles, zero changes to existing code.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/achievement.dart` | **Create** | Model |
| `lib/models/user_stats.dart` | **Modify** — add achievement/title/contribution fields | Model |
| `lib/services/achievement_registry.dart` | **Create** — static catalog | Service |
| `lib/services/gamification_service.dart` | **Create** — event bus | Service |
| `lib/services/storage_service.dart` | **Modify** — persist achievement ids + title fields | Service |
| `lib/presenters/stats_presenter.dart` | **Modify** — add `unlockAchievement()`, `unlockTitle()`, `setActiveTitle()` | Presenter |
| `lib/presenters/profile_presenter.dart` | **Create** — aggregation layer for ProfileView | Presenter |
| `lib/presenters/fasting_presenter.dart` | **Modify** — route XP through GamificationService | Presenter |
| `lib/presenters/quest_presenter.dart` | **Modify** (from Plan 005) — route XP through GamificationService | Presenter |
| `lib/views/stats_view.dart` | **Rename → profile_view.dart** + restructure into 6 sections | View |
| `lib/views/screens/achievement_list_screen.dart` | **Create** | View |
| `lib/views/widgets/achievement_badge.dart` | **Create** | View |
| `lib/views/widgets/module_activity_card.dart` | **Create** | View |
| `lib/views/widgets/title_selector_sheet.dart` | **Create** | View |
| `lib/views/widgets/xp_breakdown_bar.dart` | **Create** | View |

---

## Implementation Order

1. [ ] Define `Achievement` model + `AchievementRegistry` (no deps)
2. [ ] Add achievement/title/contribution fields to `UserStats` — update `fromJson`/`toJson` with migration defaults
3. [ ] Add new storage keys to `StorageService` — backward-compatible defaults
4. [ ] Add `unlockAchievement()`, `unlockTitle()`, `setActiveTitle()` to `StatsPresenter`
5. [ ] Create `GamificationService` — wire to `StatsPresenter`, implement `fireEvent()`
6. [ ] Refactor `FastingPresenter` to route XP through `GamificationService` (fasting achievements wired here)
7. [ ] Refactor `QuestPresenter` (Plan 005) — same treatment for quests
8. [ ] Create `ProfilePresenter` — inject `StatsPresenter` + `FastingPresenter`
9. [ ] Restructure `StatsView` → `ProfileView` — Sections A–F, wire `ListenableBuilder` to `ProfilePresenter`
10. [ ] Build `AchievementBadge` widget + `AchievementListScreen`
11. [ ] Build `ModuleActivityCard` widget
12. [ ] Build `TitleSelectorSheet` + `XpBreakdownBar` widgets
13. [ ] UX pass — glow animations on legendary badges, title equip feedback, module ring pulse

---

## RPG Impact

- **XP flow unchanged** — `StatsPresenter.addXp()` still does the math; `GamificationService` just adds routing + attribution
- **New XP sources** — achievements award bonus XP on unlock (defined in `Achievement.xpReward`)
- **Streak visible** — fasting streak days shown on profile (motivates continuity)
- **Title motivation** — players grind toward "Iron Will" or "OMAD Warrior", creating medium-term goals
- **Module unlocking** — locked modules on the activity row tease future content without breaking current flow

---

## Integration With Existing Plans

| Plan | Relationship |
|---|---|
| Plan 001 (Nav Hub) | `ModuleActivityCard` in Section D can link directly to Hub module cards — same widget family |
| Plan 005 (Quest Overhaul) | `QuestPresenter` routes XP through `GamificationService`; quest streaks contribute to `moduleActivity` |

Both plans should be completed **before** implementing Sections D–F of `ProfileView`, but Systems 1–4 (model/service/presenter layer) can land independently.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| UserStats JSON migration — existing users have no achievement fields | `fromJson` defaults: `unlockedAchievementIds: []`, `moduleXpContributions: {}` |
| Achievement double-unlock (same id fired twice) | `unlockAchievement()` is a no-op if id already in list |
| GamificationService circular dependency (owns StatsPresenter ref) | Inject `StatsPresenter` into service constructor; service does not hold a `FastingPresenter` ref |
| ProfilePresenter injected into HomeScreen grows unwieldy as modules increase | `ModuleActivitySummary` is data-only; new modules add a factory method in their own presenter, not in `ProfilePresenter` |
| Achievement gallery with 50+ achievements feels overwhelming | Default shows only earned; locked badges are silhouettes; "VIEW ALL" is secondary CTA |

---

## Acceptance Criteria

- [ ] Any module can fire a `GamEvent` and have XP, stat contribution, and achievement tracked — with zero changes to `StatsPresenter`
- [ ] `ProfileView` Section D shows at least Fasting and Quests activity rings with live data
- [ ] `ProfileView` Section E shows all earned achievements with correct rarity glow
- [ ] `ProfileView` Section F shows XP breakdown bar with correct per-module attribution
- [ ] Player can unlock, view, and equip a title; it displays in the identity header
- [ ] Achieving "Week of Silence" (7-day fasting streak) fires achievement unlock, awards XP, and displays badge in gallery
- [ ] All existing XP flows (fasting end, quest complete) work identically after `GamificationService` refactor
- [ ] `UserStats.fromJson` on old data (no achievement fields) does not crash — defaults applied
- [ ] All new widgets respect touch target ≥ 44×44px and Solo Leveling color tokens
