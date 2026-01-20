# Specification: "The System" Status Window

**Project:** Intermittent Fasting 2 (Solo Leveling Edition)  
**Architecture:** Flutter MVP (Model-View-Presenter)  
**Storage:** Shared Preferences

---

## 1. Feature Overview
The **Status Window** is the central dashboard where users view their progress. It transforms mundane wellness data (fasting and habits) into RPG progression.

**Core Features:**
*   **Dynamic Ranking:** Users progress from E-Rank to S-Rank.
*   **Attribute Points:** Users earn points to manually or automatically increase STR, VIT, AGI, INT, and SEN.
*   **The Penalty System:** Missing habits or breaking fasts results in HP loss.
*   **The Awakening:** Visualizing streaks as "Days Since Awakening."

---

## 2. Visual Specification (UI/UX)
**Theme:** Dark System Interface (Cyberpunk/Solo Leveling)

### A. Design Tokens (`lib/app_colors.dart`)
| Element | Color Code | Purpose |
| :--- | :--- | :--- |
| **background** | `#0A0E14` | Main background (Deep Black) |
| **surface** | `#1C2128` | Card/Stat box backgrounds (Slate) |
| **accent** | `#00E5FF` | "Mana Blue" - Borders, XP, Icons |
| **danger** | `#FF1744` | "HP Red" - Health bar, Penalties |
| **gold** | `#FFD600` | Level up highlights, S-Rank text |
| **textMain** | `#FFFFFF` | Primary Titles |
| **textSub** | `#94A3B8` | Subtitles and labels |

### B. UI Layout Hierarchy
1.  **Header:**
    *   Top Left: "STATUS" (Label)
    *   Top Right: Rank Hexagon (E through S)
    *   Center: Large Level Text (LV. 01) and Job Title (e.g., "Shadow Monarch")
2.  **Vitality Section:**
    *   **HP Bar:** Red gradient. Displays numerical value: `HP: 100/100`.
    *   **XP Bar:** Blue gradient. Displays numerical value: `XP: 450/1000`.
3.  **Attributes Grid (2x3):**
    *   Boxes displaying Stat Name (STR, VIT, etc.) and its current value.
    *   Glow effect if points are available to spend.
4.  **Daily Quest Log (Footer):**
    *   Simple checklist: `[X] Daily Fast` `[ ] 100 Pushups` `[X] Meditation`
    *   "Days Since Awakening" counter (Streak).

---

## 3. Technical Specification

### A. The Model Layer (`lib/models/user_stats.dart`)
```dart
typedef Attributes = ({int str, int vit, int agi, int intl, int sen});

class UserStats {
  final int level;
  final int currentXp;
  final int currentHp;
  final int statPoints; // Points available to spend
  final int streak;
  final Attributes attributes;

  const UserStats({
    required this.level,
    required this.currentXp,
    required this.currentHp,
    required this.statPoints,
    required this.streak,
    required this.attributes,
  });

  // Must include fromJson / toJson for SharedPrefs
}
```

### B. The Presenter Layer (`lib/presenters/stats_presenter.dart`)
**Logic Rules:**
*   **XP Logic:** $NextLevelXP = Level^2 \times 100$.
*   **Rank Logic:**
    *   Level 1-10: E-Rank
    *   Level 11-20: D-Rank
    *   Level 21-30: C-Rank (and so on...)
*   **Stats Impact:**
    *   Increasing VIT increases Max HP.
    *   Increasing STR increases XP gain from Habits.
*   **State Management:** Extends `ChangeNotifier`. Exposes formatted strings for the View.

### C. The View Layer (`lib/views/stats_view.dart`)
*   **Widget:** `StatScreen` (Stateless).
*   **Listener:** `ListenableBuilder(listenable: presenter, ...)`
*   **Dependency:** Constructor injection of `StatsPresenter`.

---

## 4. Implementation Phases (AI Prompts)

**Phase 1: Foundation (Data & Storage)**
> "Create the UserStats model and StorageService for my Flutter app. Use the MVP architecture. Include a Dart 3 Record for Attributes (STR, VIT, AGI, INT, SEN). Persistence must use shared_preferences. Follow the Technical Spec for field names."

**Phase 2: Logic (The Presenter)**
> "Implement the StatsPresenter extending ChangeNotifier. Add logic for: 1. Leveling up ($Level^2 \times 100$). 2. Ranking system (E to S Rank based on Level). 3. XP rewards for Fasting and Habits. 4. Stat point allocation. Use constructor injection for the StorageService."

**Phase 3: UI (The Status Window)**
> "Build the StatsView using ListenableBuilder. UI must be dark-themed with neon blue accents (AppColors.accent). Include two custom progress bars for HP and XP, a 2-column grid for attributes, and a glowing rank indicator. Use Theme.of(context) for typography and AppColors for all styling."

**Phase 4: Feedback (The Level Up Overlay)**
> "Create a LevelUpOverlay widget that triggers when the StatsPresenter detects a level change. This should be a full-screen semi-transparent modal with a gold 'LEVEL UP' animation and a button to close."
