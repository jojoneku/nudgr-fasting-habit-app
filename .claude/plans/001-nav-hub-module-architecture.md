# Feature Implementation Plan: Scalable Module Navigation (Hub Architecture)

> Status: IMPLEMENTED
> Created: 2026-03-20
> Implemented: 2026-03-21 — branch `feat/nav-hub-architecture`

---

## Feature Name
Hub + Module Navigation Architecture

## Goal
Replace the current 3-tab `NavigationBar` with a **Hub → Module** navigation pattern. The Hub is a "System Interface" (RPG world map) showing all modules as cards. Tapping a card pushes into that module full-screen. The bottom nav shrinks to 2 permanent items: **Hub** and **Character**. This scales to unlimited modules without ever touching the nav bar again — just add a new card to the grid.

## Spec Reference
No existing spec — this is a structural/navigation refactor. No model or persistence changes.

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/views/home_screen.dart` | Rewrite → `AppShell` (2-item bottom nav) | View |
| `lib/views/hub_screen.dart` | **Create** — module card grid landing page | View |
| `lib/views/settings_screen.dart` | **Create** — extract from buried AlertDialog | View |
| `lib/views/widgets/module_card.dart` | **Create** — reusable module card widget | View |
| `lib/views/tabs/timer_tab.dart` | Add own AppBar (none today) | View |
| `lib/views/tabs/quests_tab.dart` | Move add/edit AppBar actions here from HomeScreen | View |
| `lib/views/stats_view.dart` | Add settings gear entry point | View |

## Interface Definitions

```dart
// === AppShell (replaces HomeScreen) ===
// Owns presenter init + WidgetsBindingObserver
// bottom nav: Hub (0) | Character (1)
class AppShell extends StatefulWidget { }

// === HubScreen ===
// Uses a callback-per-module pattern so new modules never require a new constructor param.
// Each module registers a subtitle getter and a navigator callback at AppShell level.
class HubScreen extends StatelessWidget {
  final FastingPresenter fastingPresenter;
  final StatsPresenter statsPresenter;
  // Extra subtitle overrides: moduleId → subtitle string getter
  // Populated by AppShell as new modules (Nutrition, Activity, Treasury) are added.
  // e.g. { 'calories': () => nutritionPresenter.summaryLabel }
  final Map<String, String Function()> moduleSubtitleGetters;
  final Map<String, VoidCallback> moduleOnTapOverrides;
  // GridView of ModuleCards — Navigator.push on tap
}

// ⚠️ Scalability contract: when Plans 002/003/004 unlock their Hub cards,
// AppShell passes the new presenter's subtitle getter and onTap into these maps.
// HubScreen itself never gains new constructor params for individual modules.

// === ModuleCard ===
class ModuleCard extends StatelessWidget {
  final String title;
  final String rpgName;       // e.g. "Discipline Protocol"
  final IconData icon;
  final String? subtitle;     // Live summary: "Fasting now", "3/5 done today"
  final bool isLocked;        // Future modules: shown at reduced opacity
  final VoidCallback? onTap;
  final Color accentColor;
}

// === SettingsScreen ===
class SettingsScreen extends StatelessWidget {
  final FastingPresenter presenter;
  // All existing settings dialog content moved here as a proper screen
}
```

## Implementation Order
1. [x] Create `ModuleCard` widget — standalone, no presenter dependency
2. [x] Create `HubScreen` — GridView of ModuleCards, `Navigator.push` to module screens
3. [x] Rewrite `HomeScreen` → `AppShell` — 2-item bottom nav (Hub | Character)
4. [x] Give `TimerTab` its own AppBar when pushed as a full screen (wrapped in HubScreen push)
5. [x] Move `_showQuestDialog()` + add/edit actions into `QuestsTab` own AppBar
6. [x] Create `SettingsScreen` — move AlertDialog contents to a proper push route
7. [x] Add settings gear icon entry point in `StatsView` header
8. [ ] UX verification — all nav flows, back button, presenter lifetime

## RPG Impact
- XP awarded: none (navigation refactor only)
- Level/streak affected: no
- Notifications triggered: no
- RPG aesthetic benefit: Hub becomes a "System Interface / World Map" — each module is a Zone. Locked future modules tease the roadmap in-universe.

## Risks

| Risk | Mitigation |
|---|---|
| Presenters must survive `Navigator.push` | Keep creation in `AppShell`; pass refs down by constructor |
| `QuestsTab` currently receives `onAddQuest` callback from `HomeScreen` | Move `_showQuestDialog()` fully into `QuestsTab` |
| Settings needs `FastingPresenter` for export/import | Pass as constructor param to `SettingsScreen` |
| `WidgetsBindingObserver` (app resume reload) | Stays in `AppShell.initState()` — unaffected |

## UX Verification
- [ ] Primary CTA in bottom 30% of screen (fasting START button unchanged)
- [ ] All touch targets ≥ 44×44px (module cards min 160px tall)
- [ ] Micro-animations 150–300ms (card press feedback)
- [ ] No animation > 400ms
- [ ] Glanceable status visible in < 1 second (Hub cards show live summaries)
- [ ] Back button from any module returns to Hub correctly

## Module Map (for Hub cards)

| Module | RPG Name | Icon | Accent | Status |
|---|---|---|---|---|
| Fasting | Discipline Protocol | `timer` | `AppColors.primary` | Active |
| Habits/Quests | Quest Board | `MdiIcons.swordCross` | `AppColors.secondary` | Active |
| Calories | Alchemy Lab | `MdiIcons.flask` | `AppColors.gold` | Locked |
| Activity | Training Grounds | `MdiIcons.run` | `AppColors.success` | Locked |
| Finance | Treasury | `MdiIcons.bank` | amber | Locked |

## Acceptance Criteria
- [ ] Bottom nav has exactly 2 items: Hub and Character
- [ ] Hub shows 2-column card grid — active modules tappable, locked ones visible but disabled
- [ ] Fasting card → pushes `TimerTab` full-screen with back button
- [ ] Quests card → pushes `QuestsTab` full-screen with its own add/edit AppBar actions
- [ ] Character screen (StatsView) on bottom nav item 2
- [ ] Settings accessible from Character screen — no AppBar settings icon anywhere
- [ ] No logic in any `build()` method — summaries via presenter getters only
- [ ] All touch targets ≥ 44×44px
