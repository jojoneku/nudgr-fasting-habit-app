# Nudgr (The System)

> *"You do not level up by eating alone. You level up by discipline."*

**Nudgr** (formerly *The System* / *Intermittent Fasting 2*) is an opinionated, gamified personal life operating system built with Flutter. Originally designed as an RPG-style intermittent fasting tracker inspired by *Solo Leveling*, it has evolved into a comprehensive, multi-pillar lifestyle hub integrating physical discipline, nutrition tracking, personal treasury and double-entry finance, and conversational AI coaching.

---

> [!IMPORTANT]
> ### ⚠️ Personal Application — Not for Release or Distribution
> **Nudgr is a private, personal project built specifically for the author's own life workflows, daily habits, and financial management.**
>
> - **No Public Release / Not Distributed:** This application is **not** packaged for public release, app store distribution, or multi-tenant consumer use. It is shared on GitHub purely for transparency, code review, and version management.
> - **Proprietary & Private:** No license is granted to copy, redistribute, deploy, or commercially exploit this software.
> - **Requires Private Infrastructure:** The app is non-functional without private, unbundled cloud backends (dedicated Supabase project, custom AWS Lambda microservices, AI inference endpoints, and proprietary credentials).

---

## 🧭 Current Direction & Vision

What began as a gamified fasting timer has matured into a unified life management dashboard organized around four core pillars:

```
                      ┌─────────────────────────────────────────┐
                      │            Nudgr Life OS                │
                      └────────────────────┬────────────────────┘
                                           │
         ┌──────────────────┬──────────────┴─────┬──────────────────┐
         ▼                  ▼                    ▼                  ▼
┌─────────────────┐ ┌───────────────┐ ┌────────────────────┐ ┌───────────────┐
│ 1. Fasting &    │ │ 2. Nutrition  │ │ 3. Treasury &      │ │ 4. AI Coach   │
│    RPG Stats    │ │    & Macros   │ │    Finance         │ │    ("Nudgy")  │
└─────────────────┘ └───────────────┘ └────────────────────┘ └───────────────┘
```

### 1. ⚔️ Fasting & RPG Discipline ("The System")
- **Adaptive Fasting Timer:** Configurable fasting loops (16:8, 18:6, 20:4, circadian, custom) with precise notifications and window tracking.
- **Solo Leveling Progression:** Earn XP from fasting consistency and daily habits to advance from E-Rank to S-Rank.
- **RPG Attribute Matrix:**
  - **STR (Strength):** XP multipliers and discipline resilience.
  - **VIT (Vitality):** Max HP and endurance against penalties.
  - **AGI (Agility):** Fasting window adaptation and flexibility.
  - **INT (Intelligence):** Streak freeze protection and analytics.
  - **SEN (Perception):** Mindfulness, hunger cues, and reflection.
- **HP & Penalty Mechanics:** Breaking fasts prematurely or abandoning daily quests induces HP damage.
- **Daily Quests & Streaks:** Habit accountability ("Days Since Awakening") with streak maintenance.
- **Android Home Widgets:** Live glanceable fasting timer and status widgets on the home screen.

### 2. 🥗 Nutrition & Metabolic Health
- **High-Density Food Logging:** Rapid calorie and macro tracking (Protein, Carbs, Fats) with meal distribution.
- **RAG-Powered & Local Food Lookups:** Fast search across common foods, custom favorites, and historical logs.
- **Grocery Cart Management:** Dynamic grocery lists with live running totals and one-tap checkout settlement directly into the finance ledger.
- **Metabolic Trends:** Dynamic TDEE estimations, weight logging, and moving averages.

### 3. 💰 Personal Treasury & Finance (Mobile + Web)
- **Envelope-Style & Double-Entry Ledger:** Comprehensive transaction tracking across cash, bank accounts, digital wallets, credit cards, and investments.
- **Credit Card & Installment Engine:** Specialized modeling for billing cycles, statement cutoff dates, payment holds, and multi-month installment schedules.
- **Budgeting & Sinking Funds:** Flexible budget groups, recurring monthly allocations, savings targets, and set-asides.
- **Bills & Receivables:** Tracking upcoming payables, recurring subscriptions, and outstanding reimbursements.
- **Treasury Web Portal:** Companion Flutter Web application (`treasury_web_app`) providing a widescreen command center with ledger tables, budget grids, and financial analytics.

### 4. 🤖 Conversational AI Coach ("Nudgy")
- **Natural Language Quick-Logging:** Log complex multi-item expenses, meals, and hydration through conversational chat or image/receipt prompts.
- **Autonomous Tool Execution:** Nudgy reads balances, logs ledger entries, queries budgets, and updates schedules via structured tool calling.
- **Proactive Coaching & Briefings:** Context-aware daily insights, financial pacing guidance, and habit motivation.

### 5. ☁️ Sync, Resilience & Data Security
- **Offline-First Storage:** Local persistence backed by SQLite and key-value stores for seamless offline operation.
- **Realtime Cloud Synchronization:** Multi-device sync powered by Supabase with conflict resolution, Postgres RPCs, and data version guards.
- **Encrypted Local Backups:** Client-side AES-GCM encrypted backup exports (`.enc`) and cloud snapshot restoration.

---

## 🏗️ Architecture & Engineering Guardrails

The codebase follows strict architectural standards:

- **Strict MVP (Model-View-Presenter):**
  - **Models (`lib/models/`):** Immutable data transfer objects with explicit serialization (`fromJson` / `toJson`).
  - **Views (`lib/views/`):** Declarative, "dumb" UI listening to Presenters via `ListenableBuilder`. Zero business logic, calculations, or filters inside `build()`.
  - **Presenters (`lib/presenters/`):** State containers, RPG mathematics, and business orchestration.
  - **Services (`lib/services/`):** Pure I/O layers (storage abstractions, notifications, API clients).
- **Dependency Graph:** Inter-presenter dependencies are wired in unified graph containers (e.g., `TreasuryPresenters`) rather than instantiated ad-hoc inside UI shells.
- **Dual-Theme System:**
  - Dark Mode (Default): High-contrast *Solo Leveling* Dungeon palette (Obsidian, Mana Cyan, Ember Red, XP Gold).
  - Light Mode: Clean, accessible, high-contrast theme.
  - All widgets consume `Theme.of(context)` tokens exclusively; hardcoded theme values are prohibited.
- **Mobile Thumb Zone:** Critical interactive elements and primary actions are pinned to the bottom 30% of the screen with touch targets $\ge 44 \times 44$ pt.

---

## 🛠 Tech Stack

| Layer | Technologies |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) (Dart 3+ with sound null safety & pattern matching) |
| **Platforms** | Android (Mobile App & Home Widgets), Web (Treasury Portal) |
| **State Management** | MVP Pattern (`ChangeNotifier`, `ValueNotifier`, `ListenableBuilder`) |
| **Cloud & Backend** | [Supabase](https://supabase.com/) (PostgreSQL, Row Level Security, Realtime, RPCs) |
| **AI / LLM** | AWS Bedrock / Gemini API microservices with structured function calling |
| **Local Storage** | `sqflite` (SQLite), `shared_preferences`, AES-GCM file encryption |
| **Notifications & Widgets** | `flutter_local_notifications`, `home_widget` |

---

## 📂 Project Structure

```
lib/
├── models/         # Immutable domain models & serialization
├── presenters/     # Business logic, state machines, and RPG math
│   ├── treasury_presenters.dart  # Central dependency wiring for finance
│   ├── ai_coach_presenter.dart   # Nudgy conversational intelligence
│   ├── fasting_presenter.dart    # Fasting loop state machine
│   ├── nutrition_presenter.dart  # Nutrition & food logging engine
│   └── ledger_presenter.dart     # Treasury ledger & double-entry logic
├── views/          # Dumb UI widgets observing Presenters
│   ├── widgets/    # Reusable atomic design components & system UI
│   ├── web/        # Responsive screens for Treasury Web portal
│   └── screens/    # Mobile views (Hub, Fasting, Nutrition, Treasury, Quests)
├── services/       # Atomic services (StorageService, Sync, Notifications)
├── utils/          # Pure helper functions & formatters
├── app_colors.dart # Theme color token definitions (Dark & Light)
├── main.dart       # Mobile entrypoint & dependency injection
└── main_web.dart   # Web portal entrypoint
```

---

## 📚 Documentation & Specifications

Detailed technical specifications live in the [`docs/`](docs/) directory:

- **Fasting:** [`docs/fasting_loop_spec.md`](docs/fasting_loop_spec.md)
- **RPG Progression:** [`docs/stats_spec.md`](docs/stats_spec.md)
- **AI Coach & Logging:** [`docs/ai_coach_spec.md`](docs/ai_coach_spec.md), [`docs/chat_logging_coverage.md`](docs/chat_logging_coverage.md)
- **Treasury & Finance:** [`docs/expense_classification_spec.md`](docs/expense_classification_spec.md), [`docs/credit_accounts_spec.md`](docs/credit_accounts_spec.md), [`docs/treasury_web_spec.md`](docs/treasury_web_spec.md)
- **Data Security:** [`docs/data_security_spec.md`](docs/data_security_spec.md)
- **Operational Guidelines:** [`AGENTS.md`](AGENTS.md), [`CLAUDE.md`](CLAUDE.md)

---

## 📄 License & Terms

**Proprietary — All Rights Reserved.**

This repository is maintained for private personal use. It is **not** open-source software, and no permission is granted for copying, modifying, redistributing, or publishing this codebase in any form.

To report security vulnerabilities, please refer to [SECURITY.md](SECURITY.md).
