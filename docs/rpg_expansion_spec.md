# Specification: RPG Expansion — Boss Fights, Titles & the Dungeon Log

> Status: PLANNED — NOT IMPLEMENTED

**Project:** Intermittent Fasting 2 (Solo Leveling Edition)
**Architecture:** Flutter MVP (Model-View-Presenter)
**Storage:** `StorageService` (SharedPreferences impl) + Supabase sync
**Plan:** `.claude/plans/047-rpg-expansion.md`
**Date:** 2026-06-10

---

## 1. Feature Overview

The Status Window (see `docs/stats_spec.md`) gives the player a character; this expansion gives the character an *enemy* and a *legacy*.

**Core Features:**
*   **Weekly Boss Fights:** A generated composite challenge spanning fasting, nutrition, activity, and quests. One boss per ISO week. Victory = bonus XP + title progress.
*   **Titles:** Earnable display titles equipped on the Status Window. No purchases — titles are proof, not product.
*   **Dungeon Log:** A monthly/annual recap ("raid report") with a shareable summary card.

---

## 2. Visual Specification (UI/UX)

**Theme:** Dual-mode. All widgets read `Theme.of(context)` — no hardcoded `AppColors.*` tokens (rule 7). Rarity glows use `colorScheme.primary` (cyan), `tertiary` (purple), and the gold semantic used by rank badges.

### A. Boss Banner (QuestsTab, above daily quests)
1.  **Header row:** skull/gate icon · boss name ("DEMON KING OF GLUTTONY") · countdown chip ("3d 14h")
2.  **Objective list:** one row per objective — icon, label ("Complete an 18h fast"), progress bar + `1/1` fraction. Completed rows get a check + strikethrough.
3.  **Reward strip:** `+450 XP` and title badge silhouette if a title is at stake.
4.  Tap anywhere → **Boss Detail Sheet** (full flavor text, per-objective progress, history of past kills). Banner is one tap target ≥44px tall.
5.  States: *active* (default), *cleared* (gold border + "SLAIN" stamp), *failed* (dimmed, shown until Monday reset).

### B. Title Chip (StatsView identity header)
*   Active title rendered under the player name in `labelMedium`, accent color.
*   Tap → **Title Selector Sheet**: grid of titles; unlocked = full color + equip on tap; locked = silhouette + unlock hint ("Slay 4 bosses in a row"). Equip feedback ≤300ms scale/glow micro-animation.

### C. Dungeon Log Screen
1.  Segmented toggle: **MONTH / YEAR**, period stepper.
2.  Stat blocks (2-col grid): Total Fasts · Hours Fasted · Longest Fast · Longest Streak · Weight Δ · Quests Cleared · Bosses Slain · Money Tracked.
3.  Bottom 30%: primary CTA **"SHARE RAID REPORT"** → renders share card (app logo, period, top 4 stats, rank badge) via `RepaintBoundary` → PNG → `share_plus`.

---

## 3. Technical Specification

### A. Model Layer

```dart
// lib/models/boss_fight.dart
enum BossObjectiveType { longFast, proteinDays, calorieDays, stepDays, questClears }
enum BossStatus { active, cleared, failed }

class BossObjective {
  final BossObjectiveType type;
  final int target;        // hours for longFast, day-count or clear-count otherwise
  final int threshold;     // per-day bar where relevant (e.g. 10000 steps)
  // progress is NOT stored — derived from history (see Presenter rules)
}

class BossFight {
  final String weekKey;          // '2026-W24' — identity + idempotency key
  final String bossId;           // catalog archetype
  final String name;             // 'Demon King of Gluttony'
  final List<BossObjective> objectives;
  final int xpReward;
  final String? titleRewardId;
  final BossStatus status;
  final DateTime? settledAt;
  // fromJson/toJson — all fields defaulted; unknown enum names fall back safely
}
```

```dart
// lib/models/player_title.dart
class PlayerTitle {
  final String id;          // 'shadow_of_discipline'
  final String name;        // 'Shadow of Discipline'
  final String flavor;      // unlock condition copy
}

class TitleRegistry {
  static const List<PlayerTitle> all = [/* level, streak, fast-count, boss-kill titles */];
  static PlayerTitle? find(String id);
}
```

`UserStats` additions: `List<String> unlockedTitleIds` (default `[]`), `String? activeTitleId` (default `null`) — field names match Plan 008 for forward compatibility.

### B. Presenter Layer — `BossPresenter` Logic Rules

*   **Week identity:** ISO week, Monday 00:00 *local*. `weekKey(DateTime)` is a pure helper in `lib/utils/date_utils.dart`.
*   **Deterministic generation:** `Random(weekKey.hashCode ^ rankIndex)` selects archetype + objectives from a static catalog. No network, no persisted RNG state.
*   **Difficulty by rank:**

| Rank | Objectives | Sample targets |
|---|---|---|
| E–D | 2 | 14h fast, protein 3/7 days |
| C–B | 3 | 16h fast, protein 4/7, 8k steps ×2 |
| A–S | 4 | 18h fast, protein 5/7, 10k steps ×2, 5 quest clears |

*   **Derived progress:** `progressFor(objective)` reads `FastingPresenter.history`, `NutritionPresenter.history` + `goals`, `ActivityPresenter.history`, `QuestPresenter.quests[].completedDates`, filtered to the boss week. Progress is recomputed on demand — never incremented.
*   **Settle algorithm (on init / resume):** while `storedBoss.weekKey < currentWeekKey`: recompute final progress from history → mark `cleared`/`failed` → if cleared and not previously settled, `addXp(xpReward)` + `unlockTitle(titleRewardId)` → append to `bossHistory` → generate next week. Idempotent via `weekKey` presence in history. This mirrors `QuestPresenter`'s penalty walk-forward.
*   **XP routing:** `StatsPresenter.addXp()` direct (status quo); all boss math lives in the presenter — Views render getters only.

### C. Storage & Sync

*   Keys `rpg_boss_state` / `rpg_boss_history` on `StorageService`; titles persist inside `userStats` JSON.
*   New `SyncDomain.rpgMeta` → single-row upsert to `rpg_meta` (jsonb `data`, `updated_at`), last-write-wins, modeled on `_pushFastingState()`. Titles sync free via `SyncDomain.userProfile`. Supabase migration applied manually (house rule).
*   `markDirty(SyncDomain.rpgMeta)` after settle/generate; domain added to sign-out flush/survival lists.

### D. Notifications

*   `NotificationPreferences.bossFightsEnabled` (default `true`).
*   Week start: Monday 09:00 — "A Gate has opened. [Boss name] awaits."
*   Last chance: Sunday 18:00, only if boss still `active` with incomplete objectives.
*   Both via the existing one-shot scheduling path; cancelled/rescheduled on each settle cycle.

### E. `DungeonLogPresenter`

Read-only aggregator (no storage writes, no XP). Inputs: fasting history, nutrition/weight logs, quest data, boss history, finance `MonthlySummary`. Exposes `DungeonLogReport buildReport(period)` with pre-formatted display strings; weight delta = first vs last `WeightEntry` in period; empty periods produce zeroed report, never null.

---

## 4. Implementation Phases (AI Prompts)

**Phase 1: Foundation**
> "Create `BossFight`, `BossObjective`, `PlayerTitle` models and `TitleRegistry`. Add `unlockedTitleIds`/`activeTitleId` to `UserStats` with backward-compatible `fromJson` defaults. Add boss storage keys + methods to `StorageService` and `LocalStorageService`."

**Phase 2: Boss Logic**
> "Implement `BossPresenter`: deterministic weekly generation seeded by ISO week key + rank, derived objective progress from injected presenters' histories, and the idempotent multi-week settle walk-forward on init. Unit-test offline settle across 3 missed weeks."

**Phase 3: Titles + Sync**
> "Add `unlockTitle`/`setActiveTitle`/`displayTitle` to `StatsPresenter`. Add `SyncDomain.rpgMeta` push/pull to `SyncService` following the fastingState upsert pattern."

**Phase 4: UI**
> "Build the Boss Banner on QuestsTab, Boss Detail Sheet, Title Selector Sheet, and the title chip in StatsView. Theme-aware colors only; `ListenableBuilder`; zero logic in `build()`."

**Phase 5: Dungeon Log**
> "Implement `DungeonLogPresenter` and `DungeonLogScreen` with month/year toggle and the `RepaintBoundary` → `share_plus` share card. Add `share_plus` to pubspec."
