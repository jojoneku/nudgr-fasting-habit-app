# Plan 006 — Fasting Module Improvements

**Status:** Awaiting Approval
**Branch:** `feat/fasting-module-improvements`
**Inspired by:** Zero, Fastic, LIFE Fasting Tracker
**Note:** `FastingPresenter` will be modified again by **Plan 008** (Gamification Overhaul) to route XP through `GamificationService`. Keep XP calls via `StatsPresenter.addXp()` for now — Plan 008 refactors them.

---

## Goal

Close the gap between the fasting spec and what's actually built, then layer in the top differentiator from competing apps — **metabolic phase gates** — reframed as an RPG progression system. The result: a fasting loop that feels complete, reactive, and alive.

---

## Research: What Top Apps Do

| App | Killer Feature | Steal It? |
|---|---|---|
| **Zero** | Body-state timeline (Fat Burn → Ketosis → Autophagy markers on timer ring) | **Yes — RPG-ify as Phase Gates** |
| **Fastic** | Water/hydration reminders + holistic habit loop | Partial — fits Quest system |
| **LIFE** | Social fasting circles, accountability | No — out of scope |
| **DoFasting** | XP-like rewards tied to completing the full window | Already in spec |
| **BodyFast** | Adaptive protocols, weekly goal tracking | Partial — weekly goal counter |

---

## Gap Analysis: Spec vs. Current Code

| Spec Requirement | Current State | Gap |
|---|---|---|
| Completion modal with stats (XP, HP, streak) | Plain `SnackBar` | **Missing** |
| "Overdrive" mode past goal (red/orange UI + bonus time) | Not implemented | **Missing** |
| Short fast < 10 min → "Discard Session?" | Not implemented | **Missing** |
| 12h and 14h protocol options | UI only shows 16/18/20/24 | **Missing** |
| `FastingLog.note` journal entry | Field exists, zero UI | **Missing** |
| Constructor injection for services | Direct instantiation in presenter | **Architecture violation** |

---

## Improvements Breakdown

### Phase 1 — Fix the Spec Gaps (Correctness)

**1A. Fast Completion Modal**
Replace the SnackBar with a proper bottom sheet / full-screen overlay:
- Shows: `Total Time`, `XP Earned`, `HP Change`, `Current Streak`
- Reuses and extends `LevelUpOverlay` — pass an optional `FastCompletionData` payload
- If a level-up happened during the fast, chains into the level-up animation after dismiss

**1B. Overdrive Mode**
When `elapsedSeconds > targetSeconds` while fasting:
- Ring color shifts to `AppColors.danger` (red/orange)
- Timer label changes to `"OVERDRIVE +HH:MM:SS"` (showing bonus time)
- `FastingPresenter` exposes `bool get isOvertime` and `int get overtimeSeconds`
- Bonus XP: `+5 XP per overtime hour` on top of existing formula

**1C. Short Fast Discard Prompt**
In `_showStopFastDialog()`, add a pre-check:
- If `elapsedSeconds < 600` (10 min): show "Discard Session?" dialog
- On confirm discard: call a new `presenter.discardFast()` — resets state with no XP, no HP penalty, no history entry

**1D. Protocol Selector Expansion**
Add `12` and `14` to the protocol list so it matches the spec:
```
[12:12, 14:10, 16:8, 18:6, 20:4, OMAD]
```

---

### Phase 2 — Phase Gate System (RPG Metabolic Milestones)

The standout feature from Zero, re-skinned as Solo Leveling lore. As the fast progresses, the user enters new "phases" that unlock on the timer ring.

**Phase Definitions:**

| Phase | Trigger | RPG Label | Ring Color |
|---|---|---|---|
| I — Sugar Burn | 0h – 4h | "Glycogen Depletion" | Neutral grey |
| II — Fat Burn | 4h – 8h | "Lipolysis Activated" | `secondary` cyan |
| III — Ketosis | 8h – 16h | "Ketone Mode" | `primary` purple |
| IV — Autophagy | 16h+ | "Cell Purge Protocol" | Gold |

**Implementation:**

- New `FastingPhase` enum in `lib/models/` with `label`, `minHours`, `color`
- `FastingPresenter` exposes `FastingPhase get currentPhase` — pure getter derived from `elapsedSeconds`
- `TimerTab` ring progress color dynamically maps to `currentPhase.color`
- New small label below the percentage: `"⬡ PHASE III — KETONE MODE"`
- Milestone notifications already exist in `NotificationService` — add phase transitions as notification triggers

---

### Phase 3 — Fast Journal (Note Entry)

`FastingLog.note` is already in the model and persisted — it just has no UI.

- After the completion modal is dismissed, show an optional single-line `TextField`: *"Add a note to this fast…"*
- In `HistoryTab`, show note text below the fast duration if non-null
- `FastingPresenter.updateLog()` already handles saving — just call it after note entry

---

### Phase 4 — Architecture Fix (Constructor Injection)

`FastingPresenter` violates Rule 6 — it instantiates services directly:
```dart
// Current (wrong)
final NotificationService _notificationService = NotificationService();
final StorageService _storageService = StorageService();
```
Fix: inject both via constructor, same pattern as `StatsPresenter`.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/fasting_phase.dart` | **Create** | Model |
| `lib/models/fasting_log.dart` | Modify — no new fields needed | Model |
| `lib/presenters/fasting_presenter.dart` | Modify — constructor injection, `isOvertime`, `overtimeSeconds`, `currentPhase`, `discardFast()` | Presenter |
| `lib/views/tabs/timer_tab.dart` | Modify — phase label, overdrive color, protocol expansion, discard check | View |
| `lib/views/widgets/level_up_overlay.dart` | Modify — extend to support `FastCompletionData` payload | View |
| `lib/views/tabs/history_tab.dart` | Modify — show note if non-null | View |
| `lib/main.dart` | Modify — inject services into `FastingPresenter` | Wiring |

---

## Interface Definitions

```dart
// lib/models/fasting_phase.dart
enum FastingPhase {
  sugarBurn(label: 'Glycogen Depletion', minHours: 0),
  fatBurn(label: 'Lipolysis Activated', minHours: 4),
  ketosis(label: 'Ketone Mode', minHours: 8),
  autophagy(label: 'Cell Purge Protocol', minHours: 16);

  final String label;
  final int minHours;
  const FastingPhase({required this.label, required this.minHours});
}

// FastingPresenter new public API
bool get isOvertime;            // elapsedSeconds > fastingGoalHours * 3600
int get overtimeSeconds;        // elapsedSeconds - targetSeconds (clamped to 0)
FastingPhase get currentPhase;  // derived from elapsedSeconds, no storage needed
Future<void> discardFast();     // reset with no XP/penalty/history

// FastCompletionData (passed to completion modal)
class FastCompletionData {
  final int xpEarned;
  final int hpChange;
  final double durationHours;
  final bool wasSuccess;
}
```

---

## Implementation Order

1. [ ] Architecture fix — constructor injection in `FastingPresenter` + wire in `main.dart`
2. [ ] `FastingPhase` enum model
3. [ ] Presenter: `isOvertime`, `overtimeSeconds`, `currentPhase`, `discardFast()`
4. [ ] Timer tab: overdrive color + label, phase gate label, protocol expansion, discard dialog
5. [ ] Completion modal — extend `LevelUpOverlay` or create `FastCompletionModal`
6. [ ] Fast journal note — post-modal `TextField` + `HistoryTab` display
7. [ ] UX verification pass

---

## RPG Impact

- **XP:** Overtime bonus (+5 XP/hr extra). No other XP formula changes.
- **Streaks:** Discard path bypasses streak reset (was an unfair penalty for mis-taps).
- **Notifications:** Phase gate transitions fire milestone notifications (reuses existing channel).
- **Completion modal:** Streak count displayed — reinforces the "Days Since Awakening" narrative.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Phase color clashes with eating window accent | Phase colors only applied while `isFasting == true` |
| Discard prompt fires for first-ever fast (no history) | `discardFast()` is state-safe even on empty history |
| Completion modal level-up chaining causes double overlay | Use a `showLevelUp` flag in `TimerTab` state, not reactive listener |
| Protocol expansion breaks stored `fastingGoalHours` (12/14 new values) | `StorageService` already stores as `int` — no migration needed |

---

## Acceptance Criteria

- [ ] Ending a successful fast shows a modal (not SnackBar) with XP, HP, and streak
- [ ] Overtime past goal turns ring red and shows bonus time counter
- [ ] Stopping a fast under 10 min offers a "Discard" option with no penalty
- [ ] Phase gate label updates as timer progresses (visible below % text)
- [ ] Ring color changes at each phase boundary during active fast
- [ ] 12h and 14h are selectable protocols
- [ ] Optional note can be added after fast completion; note shows in history
- [ ] `FastingPresenter` receives `NotificationService` and `StorageService` via constructor

---

*Present this plan for approval before writing any code.*

Sources:
- [30 Best Intermittent Fasting Apps (2025)](https://appquipo.com/blog/best-intermittent-fasting-apps)
- [Develop an App Like Zero (2025)](https://theintellify.com/develop-intermittent-fasting-apps-like-zero/)
- [Top 10 Free Fasting Apps 2025](https://appquipo.com/blog/free-fasting-app)
