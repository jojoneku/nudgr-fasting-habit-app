# Intermittent Fasting 2: The System

> "You do not level up by eating alone. You level up by discipline."

**The System** is a gamified intermittent fasting and habit-tracking application built with Flutter. Inspired by the "System" from *Solo Leveling*, it turns wellness discipline into an RPG progression game where you gain XP, level up, and increase your stats (STR, VIT, AGI, INT, SEN) by completing daily fasting goals and habits.

## 📱 Features

### 🔹 Status Window
The central dashboard of your journey.
- **Rank System:** Progress from E-Rank to S-Rank based on your level.
- **Leveling:** Earn XP from fasting and habits. $NextLevelXP = Level^2 \times 100$.
- **Attributes:**
  - **STR:** Increases XP gain from habits.
  - **VIT:** Increases Max HP.
  - **AGI:** Reduces fasting difficulty (conceptual).
  - **INT:** Increases wisdom/streak protection.
  - **SEN:** Sensing/Mindfulness stat.
- **HP System:** Breaking a fast early or missing daily quests results in HP penalties.

### 🔹 Fasting Timer
- Track your fasting and eating windows.
- Visual progress indicators.
- Notifications for fast start/end.

### 🔹 Daily Quests
- Customizable habits (e.g., "100 Pushups", "Meditation").
- Completing quests awards XP and improves specific stats.
- Streak tracking ("Days Since Awakening").

### 🔹 Design
- **Theme:** High-contrast Dark Mode (Deep Black `#0A0E14` & Neon Blue `#00E5FF`).
- **UX:** "Thumb Zone" optimized for one-handed use. Glancable data visualization.

## 🛠 Tech Stack

- **Framework:** [Flutter](https://flutter.dev/) (Dart 3+)
- **Architecture:** MVP (Model-View-Presenter)
- **State Management:** `ListenableBuilder` + `ChangeNotifier` (Presenters)
- **Persistence:** `shared_preferences` (Abstracted via `StorageService`)
- **Notifications:** `flutter_local_notifications`
- **Icons:** `material_design_icons_flutter`

## 📂 Project Structure

```
lib/
├── models/         # Immutable Data Classes (POJOs with fromJson/toJson)
├── presenters/     # Business Logic, State, and RPG Math
├── views/          # UI Widgets (Dumb components listening to Presenters)
├── services/       # Atomic services (Storage, Notifications)
├── utils/          # Helpers (Date formatting, etc.)
└── main.dart       # Entry point & Dependency Injection
```

## 🚀 Getting Started

1.  **Prerequisites:**
    - Flutter SDK (3.4.1 or higher)
    - Android Studio / VS Code

2.  **Installation:**
    ```bash
    git clone https://github.com/jojoneku/nudgr-fasting-habit-app.git
    cd intermittent_fasting_2
    flutter pub get
    ```

3.  **Run the App:**
    ```bash
    flutter run
    ```

## 🎨 Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| **Background** | `#0A0E14` | Main App Background |
| **Surface** | `#1C2128` | Cards, Dialogs |
| **Primary** | `#00E5FF` | Mana Blue (Accents, XP) |
| **Danger** | `#FF1744` | HP Red (Health, Penalties) |
| **Success** | `#00E676` | Level Up, Completion |
| **Gold** | `#FFD600` | S-Rank Highlights |

## 🤝 Contributing

1.  Fork the repository.
2.  Create your feature branch (`git checkout -b feat/amazing-feature`).
3.  Commit your changes (`git commit -m 'Add some amazing feature'`).
4.  Push to the branch (`git push origin feat/amazing-feature`).
5.  Open a Pull Request.

---

*Provisional Name: Nudgr / The System*
