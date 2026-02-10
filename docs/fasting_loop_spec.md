# Feature Specification: Fasting & Health Tracking System

## 1. 🎯 Objective
Implement the core "Fasting Loop" mechanics for the player. This includes starting a fast, tracking elapsed time, ending a fast, and calculating XP rewards based on duration.

## 2. 🧠 Conceptual Model (The "System" Logic)

### Core Rules
- **Status:** The user is always in one of two states: `Fasting` or `Eating`.
- **Duration:** 
  - Minimum valid fast for XP: **12 hours**.
  - "Golden Ratio": Beating the user's projected goal awards bonus XP.
- **XP Calculation:** 
  - Base XP: 10 XP per hour fasted.
  - Bonus XP: +50 XP for completing the target goal.
  - Penalty: Ending early (< 50% of goal) results in 0 bonus XP.

### Class: `FastingSession`
| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | `String` (UUID) | Unique identifier. |
| `startTime` | `DateTime` | When the user clicked "Start". |
| `endTime` | `DateTime?` | Null if currently active. |
| `targetDuration` | `Duration` | The goal set by user (e.g., 16 hours). |
| `isCompleted` | `bool` | Derived: `endTime != null`. |

---

## 3. 📱 User Interface (The "HUD")

### A. The Dashboard (Home Screen)
- **Central Element:** A large circular progress indicator (The "Arc Reactor").
  - **Color:** Gradient from Cyan (`#00E5FF`) to Purple (`#D500F9`).
  - **Content:** Displays `HH:MM:SS` elapsed time.
- **State: NOT Fasting**
  - **Primary Action:** Large "INITIATE FAST" button (Bottom 30% - Thumb Zone).
  - **Selector:** Scroll wheel to pick target duration (12h, 14h, 16h, 18h, 20h, 24h).
- **State: Fasting**
  - **Primary Action:** "TERMINATE" button (Long press to confirm, prevents accidental stops).
  - **Information:** "Time Remaining" and "Projected End Time".

### B. Completion Modal (Level Up)
- Triggers when `FastingSession` ends.
- **Animation:** Particle effects or glow burst.
- **Stats Shown:** `Total Time`, `XP Earned`, `Streak Count`.

---

## 4. 🔄 Flow & Edge Cases

### Happy Path
1. User selects "16 Hours".
2. Taps "INITIATE". App saves state locally.
3. Timer counts up in foreground.
4. User taps "TERMINATE" after 16h 01m.
5. App awards XP, updates stats, shows Success Modal.

### Edge Cases
- **App Killed:** Timer uses `DateTime.now().difference(startTime)` on restart. Accuracy is maintained regardless of background state.
- **Short Fast:** If user stops < 10 mins in, ask "Discard Session?".
- **Overtime:** If user exceeds goal, UI turns "Overdrive" color (Red/Orange) and tracks "Bonus Time".

---

## 5. 🛠 Technical Implementation Notes

### Presenter: `FastingPresenter`
- `void startFast(Duration target)`
- `void endFast()`
- `String get formattedTimer` (Getters for UI consumption)
- `double get progressPercentage` (0.0 to 1.0)

### Notifications
- **Trigger:** Schedule local notification at `startTime + targetDuration`.
- **Message:** "System Alert: Fuel Depletion Complete. Refeed Authorized."
