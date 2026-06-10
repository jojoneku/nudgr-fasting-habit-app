# Plan 047 — RPG Expansion: Boss Fights, Titles & the Dungeon Log

> Status: PLANNED — NOT IMPLEMENTED

**Author:** System Architect
**Date:** 2026-06-10
**Spec:** [docs/rpg_expansion_spec.md](../../docs/rpg_expansion_spec.md)
**Depends on:** None hard. Overlaps Plan 008 (see Conflict Check).

---

## Conflict Check

| Check | Question | Finding |
|---|---|---|
| **File overlap** | Plan 008 modifies `user_stats.dart`, `stats_presenter.dart`, `stats_view.dart` | Plan 008 is PARTIAL and stalled. This plan implements the **title subset** of 008 directly; 008's Title System section is absorbed here — annotate 008 when this ships |
| **Model overlap** | Plan 008 defines `unlockedTitleIds` / `activeTitle` on `UserStats` | Same fields, same names — intentionally compatible so 008 can still land later |
| **XP routing** | This plan calls `StatsPresenter.addXp()` directly | Acceptable — every live module does today (GamificationService was never built). Route through it later if 008 completes |
| **HubScreen** | Boss banner lives on QuestsTab + StatsView, not a new Hub card | No Hub changes |
| **Dependency order** | None | Ship standalone |

---

## Goal

The Status Window levels up, but nothing in The System *fights back*. Three sub-features deepen the RPG loop:

1. **Weekly Boss Fights** — a generated weekly composite challenge spanning fasting, nutrition, activity, and quests. Beat the boss → bonus XP + a title.
2. **Titles & Cosmetics** — earnable, equippable display titles on the Status Window. Pure progression flex; no purchases, ever.
3. **Dungeon Log** — a monthly/annual recap screen ("raid report") with a shareable summary card.

---

## System 1 — Weekly Boss Fights

### Progress is derived, never counted

Each presenter already exposes everything a boss objective needs — measured **from persisted history**, not live counters:

| Objective type | Source | Measurement |
|---|---|---|
| `longFast` (e.g. one ≥18h fast) | `FastingPresenter.history` (`List<FastingLog>`) | any log in week with `durationSeconds ≥ target` |
| `proteinDays` (hit protein N/7 days) | `NutritionPresenter.history` (`DailyNutritionLog`) + `goals` | count days where `totalProtein ≥ proteinGoal` |
| `calorieDays` (stay under goal N days) | same | count days where goal met |
| `stepDays` (10k steps × N days) | `ActivityPresenter.history` (`ActivityLog.steps`) | count days `steps ≥ target` |
| `questClears` (clear N quests) | `QuestPresenter.quests` → `completedDates` | count completion date-keys inside week |

Because progress is a pure function of `(history, weekKey)`, the boss can be **settled retroactively** after any offline period — same philosophy as `QuestPresenter.checkMissedQuestsAndApplyPenalty()`'s walk-forward from `_lastPenaltyCheckDate`.

### Deterministic weekly cycle

- Week key = ISO week, Monday 00:00 local (`'2026-W24'`).
- Generation is seeded: `Random(weekKey.hashCode)` picks the boss archetype + objective mix from a static `BossCatalog`. Same week + same level band ⇒ same boss on every device — no sync race on generation.
- Difficulty scales with `StatsPresenter.rank` (E/D = 2 objectives, easy targets … A/S = 4 objectives, 18h+ fasts). Reward XP scales with `nextLevelXp` fraction so it stays meaningful at high level.
- On `_init()`: if persisted boss `weekKey != currentWeekKey`, settle every elapsed week in order (derive progress from history, award if cleared, append to `bossHistory`), then generate the current week's boss. Deterministic, idempotent, offline-safe.

### Rewards & notifications

- Victory: `_stats.addXp(boss.xpReward)` + first-kill / streak-kill title unlocks.
- Defeat: no HP penalty in v1 (bosses are aspirational, not punitive — penalty system already owns punishment).
- Notifications via existing one-shot patterns in `notification_service.dart`: boss-week start (Mon 09:00) and last-chance reminder (Sun 18:00, only if ≥1 objective incomplete). New `NotificationPreferences.bossFightsEnabled` flag (default on), respecting the prefs-gating pattern used by `questNotificationsEnabled`.

## System 2 — Titles

- `TitleRegistry` — static catalog (id, name, flavor, unlock condition description), mirroring Plan 008's achievement-registry shape. Seed set: level/rank milestones ("Shadow of Discipline" — 30-day streak, "Iron Stomach" — ten 18h+ fasts), boss kills ("Demon Slayer", "Kingslayer" — 4 boss kills in a row).
- `UserStats` gains `unlockedTitleIds: List<String>` + `activeTitleId: String?` (fromJson defaults `[]` / `null` — old blobs must not crash).
- `StatsPresenter` gains `unlockTitle()`, `setActiveTitle()`, `displayTitle` getter (`activeTitle ?? jobTitle`). Unlock is a no-op if already owned.
- StatsView header shows the active title under the player name; tap → `TitleSelectorSheet` (unlocked = selectable, locked = silhouette + hint).
- Sync: rides the existing `SyncDomain.userProfile` push (`userStats.toJson()` already travels whole) — **zero sync schema work for titles**.

## System 3 — Dungeon Log

- `DungeonLogPresenter` — read-only aggregator (no own storage, no XP): injected with Fasting/Nutrition/Stats/Quest presenters + `StorageService` for finance monthly summaries. Computes per-month and per-year: total fasts + hours, longest fast, longest streak, weight delta (`weightLog` first/last in range), total XP gained (approximated from level/XP snapshots in boss history entries), quests cleared, bosses slain, money tracked (`MonthlySummary` totals).
- `DungeonLogScreen` — entered from StatsView; month/year segmented toggle; stat blocks styled as a raid report.
- Share card: stats summary widget wrapped in `RepaintBoundary` → `toImage()` → temp PNG via `path_provider` → **`share_plus`** (NOT in pubspec — must be added).

---

## Storage & Sync

```dart
// StorageService additions
static const String keyBossState = 'rpg_boss_state';       // current BossFight
static const String keyBossHistory = 'rpg_boss_history';   // settled List<BossFight>
Future<void> saveBossState(BossFight? boss);
Future<BossFight?> loadBossState();
Future<void> saveBossHistory(List<BossFight> history);
Future<List<BossFight>> loadBossHistory();
```

- New `SyncDomain.rpgMeta` enum value; push/pull follows the `_pushFastingState()` upsert pattern (single `rpg_meta` row per user, `data` jsonb, `updated_at` last-write-wins). Supabase table migration is **manual** per house deploy rule.
- `markDirty(SyncDomain.rpgMeta)` after every boss settle/generate. Add the new domain to the sign-out survival list (synced `SyncDomain`s survive re-login — see PR #185 pattern).

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/boss_fight.dart` | **Create** — `BossFight`, `BossObjective`, enums, json | Model |
| `lib/models/player_title.dart` | **Create** — `PlayerTitle` + `TitleRegistry` catalog | Model |
| `lib/models/user_stats.dart` | Modify — `unlockedTitleIds`, `activeTitleId` (defaulted) | Model |
| `lib/models/notification_preferences.dart` | Modify — `bossFightsEnabled` | Model |
| `lib/presenters/boss_presenter.dart` | **Create** — generation, settle, progress derivation | Presenter |
| `lib/presenters/dungeon_log_presenter.dart` | **Create** — recap aggregation | Presenter |
| `lib/presenters/stats_presenter.dart` | Modify — title unlock/equip API | Presenter |
| `lib/services/storage_service.dart` + `local_storage_service.dart` | Modify — boss keys/methods | Service |
| `lib/services/sync_service.dart` + `lib/models/sync_queue_entry.dart` | Modify — `SyncDomain.rpgMeta` | Service |
| `lib/services/notification_service.dart` | Modify — boss week-start / last-chance one-shots | Service |
| `lib/views/quests/widgets/boss_banner.dart` | **Create** — weekly boss card on QuestsTab | View |
| `lib/views/widgets/boss_detail_sheet.dart` | **Create** — objectives + progress bars | View |
| `lib/views/widgets/title_selector_sheet.dart` | **Create** | View |
| `lib/views/stats_view.dart` | Modify — active title in header, Dungeon Log entry | View |
| `lib/views/dungeon_log_screen.dart` | **Create** | View |
| `pubspec.yaml` | Modify — add `share_plus` | — |

## Implementation Order

1. [ ] Models: `BossFight`/`BossObjective`/`PlayerTitle` + `UserStats` fields (json defaults tested)
2. [ ] Storage keys + methods; `SyncDomain.rpgMeta` + push/pull + manual Supabase migration
3. [ ] `StatsPresenter` title API + tests
4. [ ] `BossPresenter`: catalog, seeded generation, settle-on-init walk-forward, progress getters + tests (offline multi-week settle is the critical test)
5. [ ] Notifications: prefs flag + week-start/last-chance scheduling
6. [ ] Views: boss banner + detail sheet, title chip + selector, ListenableBuilder only
7. [ ] `DungeonLogPresenter` + screen + share card (`share_plus`)
8. [ ] UX pass — boss-kill celebration overlay (reuse `LevelUpOverlay` pattern, ≤400ms)

One PR per numbered phase-group (models+storage / boss / titles / dungeon log) — never bundled.

## RPG Impact

- XP: boss victory = scaled bonus (target ≈ 15–25% of `nextLevelXp`); Dungeon Log awards none (read-only)
- Streaks: untouched — boss reads history, never writes module state
- Notifications: 2 new weekly one-shots, prefs-gated

## Risks

| Risk | Mitigation |
|---|---|
| Boss progress double-settles after sync pull | Settle is idempotent: keyed by `weekKey`; settled weeks in `bossHistory` are skipped |
| Presenter web (Boss needs 4 presenters) | Constructor injection of presenters already constructed in `main.dart`; Boss only *reads* their getters |
| `UserStats.fromJson` on old blobs | New fields defaulted; round-trip test required |
| `share_plus` adds platform config | Android-only target today; verify release build before merge |
| Objective targets unfair at low rank | Difficulty table per rank in catalog; clamp to user's actual goals (protein objective uses *their* `proteinGoal`) |

## Acceptance Criteria

- [ ] Same device, same week, same rank ⇒ identical boss after reinstall (deterministic generation)
- [ ] App killed Friday→opened next Wednesday: prior week settles from history, win/loss correct, new boss generated
- [ ] Boss victory awards XP once (idempotent), unlocks title, fires celebration
- [ ] Title equip persists, syncs via userProfile, and shows in StatsView header
- [ ] Dungeon Log renders a full month with zero data (empty-state copy, no crash) and shares a PNG card
- [ ] All new widgets theme-aware (`Theme.of(context)`), touch targets ≥44px, animations ≤400ms
