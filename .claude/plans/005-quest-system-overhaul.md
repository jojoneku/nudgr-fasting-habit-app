# Plan 005 — Quest System Overhaul: From Reminders to Habit Architecture
**Status:** DRAFT — Awaiting Approval

---

## Goal

Transform the Quest tab from a basic reminder list into a psychologically-grounded habit-building system. The current module sends notifications and tracks completions, but doesn't leverage any of the mechanisms that make habits actually stick long-term.

The overhaul introduces: per-quest streaks with grace and freeze recovery, stat-linked habit identity, variable XP rewards, RPG-flavored completion feedback, habit routines (stacks), and a visual completion history. Every change maps to a specific psychological mechanism with documented research backing.

This is still "The System" — quests are Daily Missions from the System to forge the Hunter.

---

## Psychology → Feature Mapping

| Mechanism | Research | Feature |
|---|---|---|
| Habit Loop (cue→reward) | Duhigg, Clear | RPG completion celebration with stat feedback |
| Identity-based habits | Atomic Habits (Clear) | `linkedStat` ties each quest to a character attribute |
| Tiny Habits | BJ Fogg | `minimumVersion` field — log partial completion without streak break |
| Per-quest streaks | Seinfeld chain | Per-quest streak counter + calendar heat map |
| Grace period | Smashing Mag 2026 | 30-min window after midnight to log yesterday |
| Streak shield | Duolingo model | Earn shields at milestones, spend to prevent streak reset |
| Variable rewards | Skinner / Nir Eyal | Random CRITICAL COMPLETION (2× XP) — ~15% chance |
| Habit stacking | BJ Fogg, BPS study | Routines — ordered quest chains for morning/evening rituals |
| Implementation intentions | Gollwitzer | `anchorNote` field: "I do this after [existing habit]" |
| Notification fatigue | JMIR trial | Per-quest notification opt-out; smart "streak at risk" alert at EOD |
| Achievement milestones | Endowed progress | Badges at 7 / 21 / 30 / 66 / 100 day streaks |

---

## What Changes vs. What Stays

**Stays:**
- `Quest` model base fields (id, title, hour, minute, days, isEnabled, isOneTime, completedDates, xpReward, reminderMinutes)
- Notification scheduling via `NotificationService` (alarmClock mode)
- Presenter-owns-logic architecture
- XP → `StatsPresenter.addXp()` delegation

**Changes:**
- `Quest` model gains 6 new fields
- New `HabitRoutine` model
- New `QuestPresenter` split from `FastingPresenter` (quests have outgrown it)
- `QuestsTab` view fully redesigned
- Quest dialog expanded with stat + identity fields
- New `QuestDetailView` with heatmap + achievement badges
- New `RoutineEditorView`

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/quest.dart` | Modify | Model |
| `lib/models/habit_routine.dart` | Create | Model |
| `lib/models/quest_achievement.dart` | Create | Model |
| `lib/presenters/quest_presenter.dart` | Create (split from fasting_presenter) | Presenter |
| `lib/presenters/fasting_presenter.dart` | Modify (remove quest logic, inject QuestPresenter) | Presenter |
| `lib/views/tabs/quests_tab.dart` | Rewrite | View |
| `lib/views/quests/quest_detail_view.dart` | Create | View |
| `lib/views/quests/add_quest_sheet.dart` | Create (split from home_screen dialog) | View |
| `lib/views/quests/routine_editor_view.dart` | Create | View |
| `lib/views/quests/widgets/quest_mission_tile.dart` | Create | View |
| `lib/views/quests/widgets/habit_heatmap.dart` | Create | View |
| `lib/views/quests/widgets/streak_badge.dart` | Create | View |
| `lib/services/storage_service.dart` | Modify (add quest/routine keys) | Service |
| `lib/services/notification_service.dart` | Modify (add streak-at-risk notification) | Service |

---

## Interface Definitions

### Updated Quest Model

```dart
// Stat that this quest trains — connects daily behavior to character identity
// null = no stat connection (generic quest)
enum LinkedStat { str, vit, agi, intl, sen }

// How the user completed a quest
enum CompletionType { full, partial, skipped }

class Quest {
  // --- Existing fields (unchanged) ---
  final String id;
  final String title;
  final int hour, minute;
  final List<bool> days;            // 7-element, Mon-Sun
  final bool isEnabled;
  final bool isOneTime;
  final List<String> completedDates; // 'YYYY-MM-DD'
  final int xpReward;               // base XP (default 10)
  final int reminderMinutes;        // 0 = off, 5/30/60 = before
  final DateTime? lastXpAwarded;

  // --- New fields ---
  final LinkedStat? linkedStat;    // which attribute this quest builds toward
  final String? anchorNote;        // "I do this after..." — implementation intention
  final String? minimumVersion;    // "At minimum, I will..." — tiny habit fallback
  final int streakCount;           // per-quest current streak (days in a row)
  final int streakFreezes;         // available streak shields (max 3)
  final String? routineId;         // if this quest belongs to a routine

  // --- Computed (not stored) ---
  // bool get isCompletedToday
  // bool get isCompletedOn(DateTime)
  // bool get isMissedToday  // scheduled for today, past time, not completed
  // DateTime? get lastCompleted
}
```

### New: HabitRoutine Model

```dart
// A named, ordered sequence of quests executed as a ritual
// e.g. "Morning Ritual" → [Drink water, Meditate, Journal]
class HabitRoutine {
  final String id;
  final String name;               // "Morning Ritual", "Evening Wind-Down"
  final String icon;               // MDI icon name
  final String colorHex;
  final List<String> questIds;     // ordered — defines execution sequence
  final int scheduledHour;         // suggested start time for the routine
  final int scheduledMinute;

  // fromJson / toJson
}
```

### New: QuestAchievement Model

```dart
// Milestone badge earned when a quest streak hits a threshold
class QuestAchievement {
  final String id;
  final String questId;
  final int streakMilestone;  // 7, 21, 30, 66, 100
  final DateTime unlockedAt;
  final bool seen;            // false = show unlock animation on next open

  // fromJson / toJson
}
```

### QuestPresenter (new — split from FastingPresenter)

```dart
class QuestPresenter extends ChangeNotifier {
  QuestPresenter(StorageService storage, StatsPresenter stats);

  // --- State ---
  List<Quest> get quests;
  List<HabitRoutine> get routines;
  List<QuestAchievement> get unseenAchievements; // triggers unlock overlay
  bool get hasUnseenAchievements;

  // --- Daily view grouping ---
  List<Quest> get todayPendingQuests;    // scheduled today, not completed, not yet past time
  List<Quest> get todayOverdueQuests;    // scheduled today, past time, not completed
  List<Quest> get todayCompletedQuests;  // completed today
  List<Quest> get todayRoutineQuests;    // quests belonging to any routine

  // --- Completion ---
  // Returns: (xpGained, isCritical) — isCritical = variable 2× bonus triggered
  Future<(int, bool)> completeQuest(String questId, {CompletionType type = CompletionType.full});
  // ^ Awards XP, updates streak, checks for achievements, checks stat contribution

  // Grace period: allow logging yesterday's quest up to 30 min after midnight
  bool canGraceComplete(String questId); // true if within grace window
  Future<(int, bool)> graceCompleteQuest(String questId);

  // --- Streak management ---
  Future<void> spendStreakFreeze(String questId); // use a shield to prevent reset
  // Freezes earned: +1 at 7-day milestone, +1 at 30-day milestone

  // --- CRUD ---
  Future<void> addQuest(Quest);
  Future<void> updateQuest(Quest);
  Future<void> deleteQuest(String id);
  Future<void> toggleQuest(String id);

  // --- Routines ---
  Future<void> addRoutine(HabitRoutine);
  Future<void> updateRoutine(HabitRoutine);
  Future<void> deleteRoutine(String id);

  // --- Penalty (called on app load, same as before) ---
  Future<int> checkMissedQuestsAndApplyPenalty();
  // Returns total HP damage applied

  // --- Achievements ---
  Future<void> markAchievementSeen(String achievementId);

  // --- Stat contribution ---
  // Each quest linked to a stat contributes 1/21 toward a +1 stat point
  // (21 consecutive completions = +1 to linkedStat, then resets)
  double statProgressFor(String questId); // 0.0–1.0
}
```

---

## StorageService New Keys

```dart
static const keyQuestRoutines     = 'quest_routines';
static const keyQuestAchievements = 'quest_achievements';

Future<void> saveRoutines(List<HabitRoutine>);
Future<List<HabitRoutine>> loadRoutines();

Future<void> saveAchievements(List<QuestAchievement>);
Future<List<QuestAchievement>> loadAchievements();
```

(Quests themselves continue to be saved via existing `keyQuests` in `saveState()`)

---

## View Redesign: QuestsTab

### Layout — 3 sections (replacing flat list):

```
┌─────────────────────────────────────────────────────┐
│  DAILY MISSIONS                       [+ New] [Edit] │
│                                                      │
│  ┌─ MORNING RITUAL ────────────────────────────────┐ │
│  │ 🏋 Push-ups     STR ████░ streak 14 🔥  [✓]     │ │
│  │ 💧 Drink Water  VIT ██░░░ streak 5  🔥  [✓]     │ │
│  └──────────────────────────────────────────────── ┘ │
│                                                      │
│  ┌─ STANDALONE ────────────────────────────────────┐ │
│  │ 📖 Read 10 min  INT ███░░ streak 9  🔥  [✓]     │ │
│  └──────────────────────────────────────────────── ┘ │
│                                                      │
│  ┌─ MISSED ────────────────────────────────────────┐ │
│  │ 🏃 Evening Walk  [overdue — tap to log anyway]   │ │
│  └──────────────────────────────────────────────── ┘ │
│                                                      │
│  ┌─ COMPLETED TODAY ───────────────────────────────┐ │
│  │ ~~Meditate~~  ✓  streak 22 🔥                   │ │
│  └──────────────────────────────────────────────── ┘ │
└─────────────────────────────────────────────────────┘
```

### QuestMissionTile fields visible:
- Stat icon + color (STR=red, VIT=green, AGI=cyan, INT=purple, SEN=amber)
- Title (strike-through if completed)
- Stat progress ring (small, shows 21-day contribution progress)
- Streak counter + fire emoji
- Streak freeze shields (shown as ❄️ icons if available)
- Completion button (tap = full, long-press = partial / "minimum version")

### Completion Feedback:

```
[Full completion]    → RPG panel slides up:
                       "MISSION COMPLETE"
                       "+10 EXP"  [STR progress +5%]

[Critical hit ~15%]  → Same panel but:
                       "CRITICAL COMPLETION!"
                       "+20 EXP ×2 BONUS"
                       Gold particle effect

[Partial/Minimum]    → Quieter:
                       "Minimum logged — streak preserved"
                       "+5 EXP"
```

### Streak-at-risk notification (new):
- Fires at 9 PM if a quest scheduled for today is still uncompleted
- "⚔️ [Quest name] — Don't lose your [N]-day streak. You still have time."
- Only fires if `streakCount > 3` (not on new habits — avoids pressure too early)

---

## Quest Detail View (new)

Accessible via long-press on any mission tile. Shows:
- **Habit calendar heatmap** — 12-week rolling view, green = completed, grey = missed, amber = partial
- **Streak badges** — row of unlocked achievements (7, 21, 30, 66, 100 days)
- **Stat contribution bar** — "X / 21 completions toward +1 STR"
- **Anchor note** (if set): "⚓ After my morning coffee"
- **Minimum version** (if set): "At least: 5 push-ups"
- **Stats:** Longest streak, completion rate (last 30 days), total completions

---

## RPG Impact

| Action | Reward |
|---|---|
| Complete quest (full) | Base `xpReward` XP (default 10) |
| Critical Completion (~15% chance) | 2× XP |
| Complete quest (partial/minimum) | 50% of base XP — streak preserved |
| 21 consecutive completions (linked stat) | +1 to linkedStat (e.g. +1 STR) |
| Unlock 7-day milestone | +1 streak freeze shield |
| Unlock 30-day milestone | +1 streak freeze shield |
| Missed quest (no grace, no freeze) | −10 HP (existing penalty) |
| Spend streak freeze | Shield consumed, streak preserved, no HP loss |

**Stat auto-progression (new):** Quests are the primary driver of attribute growth.
- 21 consecutive completions of a STR quest → `StatsPresenter.autoIncrementAttribute(LinkedStat.str)`
- This makes the character literally embody the habits you keep

---

## Implementation Order

1. [ ] Update `Quest` model — add 6 new fields, `fromJson`/`toJson` migration-safe (new fields = nullable/defaulted)
2. [ ] Create `HabitRoutine` and `QuestAchievement` models
3. [ ] Add new StorageService keys + methods
4. [ ] Create `QuestPresenter` — migrate quest logic from `FastingPresenter` first (no new features yet)
5. [ ] Add grace period + streak logic + achievement detection to `QuestPresenter`
6. [ ] Add variable reward (critical completion) logic
7. [ ] Add stat auto-progression logic (21-day → `StatsPresenter.autoIncrementAttribute`)
8. [ ] Add streak-at-risk notification to `NotificationService`
9. [ ] Build `QuestMissionTile` widget
10. [ ] Build `HabitHeatmap` widget
11. [ ] Build `StreakBadge` widget
12. [ ] Rewrite `QuestsTab` with new grouped layout
13. [ ] Build `AddQuestSheet` (split from home_screen dialog, add new fields)
14. [ ] Build `QuestDetailView`
15. [ ] Build `RoutineEditorView`
16. [ ] Wire `QuestPresenter` into widget tree (alongside existing `FastingPresenter`)
17. [ ] UX verification — completion animation, critical hit particle effect

---

## Migration Safety

The `Quest` model gains 6 new nullable/defaulted fields. `fromJson` must handle missing keys gracefully:
- `linkedStat: null` (no stat connection by default)
- `anchorNote: null`
- `minimumVersion: null`
- `streakCount: 0` (recalculate from `completedDates` on first load if 0)
- `streakFreezes: 0`
- `routineId: null`

Streak recalculation: on first load after update, if `streakCount == 0` and `completedDates.isNotEmpty`, calculate the current streak from `completedDates` and backfill. This prevents all users losing their streaks on update.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Streak inflation via grace period | Grace period = 30 min after midnight only, not retroactive for missed days |
| Critical completion feel unfair | Cap at once per quest per day — second completion of same quest cannot crit |
| 21-day stat auto-increment overrides user-allocated points | `autoIncrementAttribute` only increments if `statPoints` is not the source — separate `autoPoints` tracking |
| Splitting `QuestPresenter` breaks `FastingPresenter` | Step 4 migrates first with no feature changes, ensuring test parity before adding new logic |
| `HabitHeatmap` widget heavy for 52 weeks of data | Render only 12 weeks (84 cells) — enough for pattern recognition without performance hit |
| `streakFreezes > 3` exploit | Cap at 3 max, no accumulation beyond cap |

---

## Acceptance Criteria

- [ ] Existing quests load correctly with zero data loss after model migration
- [ ] Per-quest streak increments on completion, resets on missed day (no freeze spent)
- [ ] Grace period: quest logged within 30 min after midnight counts as yesterday, doesn't reset streak
- [ ] Streak freeze: spending a freeze preserves streak, removes shield icon, no HP damage
- [ ] Critical completion fires ~15% of the time (verifiable in testing with mock random)
- [ ] 21 consecutive completions on a stat-linked quest triggers +1 to that stat
- [ ] Achievement badges unlock at 7/21/30/66/100 day streaks and show unseen animation
- [ ] Heatmap renders 12 weeks with correct green/grey/amber states
- [ ] Routines group their quests under a named header in the daily view
- [ ] Streak-at-risk notification fires at 9 PM only if streakCount > 3 and quest incomplete
- [ ] All touch targets ≥ 44×44px
- [ ] No logic in any `build()` method

---

*Present this plan for approval before writing any code.*
