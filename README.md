# Nudgr

A minimalist, opinionated personal life operating system built with Flutter. Nudgr unifies intermittent fasting, nutrition tracking, daily activity, personal treasury and finance, and conversational AI coaching into a single, cohesive private dashboard.

---

> [!IMPORTANT]
> ### ⚠️ Personal Application — Not for Release or Distribution
> **Nudgr is a private personal project built specifically for the author's own life workflows, daily habits, and financial management.**
>
> - **No Public Release / Not Distributed:** This application is **not** packaged for public release, app store distribution, or multi-tenant consumer use. It is maintained on GitHub purely for transparency, personal portfolio, and version control.
> - **Proprietary & Private:** No license is granted to copy, redistribute, deploy, or commercially exploit this software.
> - **Requires Private Infrastructure:** The app is non-functional without private, unbundled cloud backends (dedicated Supabase project, custom AWS Lambda microservices, private AI inference endpoints, and proprietary credentials).

---

## 🧭 Current Direction & Core Modules

Nudgr functions as a daily personal command center centered around an integrated Hub and specialized modules:

```
                      ┌─────────────────────────────────────────┐
                      │              Nudgr Hub                  │
                      └────────────────────┬────────────────────┘
                                           │
         ┌──────────────────┬──────────────┼──────────────┬──────────────────┐
         ▼                  ▼              ▼              ▼                  ▼
┌─────────────────┐ ┌───────────────┐ ┌──────────┐ ┌──────────────┐ ┌───────────────┐
│ 1. Fasting &    │ │ 2. Nutrition  │ │ 3. Move  │ │ 4. Treasury  │ │ 5. AI Coach   │
│    Habits       │ │    & Body     │ │ (Health) │ │  (Ledger/Web)│ │    ("Nudgy")  │
└─────────────────┘ └───────────────┘ └──────────┘ └──────────────┘ └───────────────┘
```

### 1. ⏱️ Fasting & Habit Tracking
- **Adaptive Fasting Timer:** Configurable fasting protocols (16:8, 18:6, 20:4, circadian, custom) with notifications for fasting and eating windows.
- **Fasting Stages:** Visual progress tracking through biological fasting milestones (blood sugar stabilization, ketosis, autophagy).
- **Daily Habits & Routines:** Custom daily checklists and task tracking with completion streaks and reminders.
- **Android Home Widgets:** Glanceable home-screen widgets for live fast status, progress rings, and quick actions.

### 2. 🥗 Nutrition, Macros & Body Composition
- **High-Density Food Logging:** Rapid entry for calories and macronutrients (protein, carbs, fat) across custom meals.
- **Local & Fast Search:** Quick item search across favorite foods, recent entries, and historical logs.
- **Integrated Grocery Cart:** Live trip shopping list with running total calculations and one-tap checkout settlement directly into the finance ledger.
- **Body & Weight Tracking:** Weight logging, body circumference measurements, moving averages, and dynamic TDEE calculations.

### 3. 👟 Activity & Movement
- **Health Connect Integration:** Automatic background synchronization with Google Health Connect for steps and walking distance.
- **Daily Activity Goals:** Real-time progress monitoring on the Hub dashboard alongside wellness metrics.

### 4. 💰 Personal Treasury & Finance (Mobile + Web)
- **Multi-Account Ledger:** Double-entry-inspired transaction tracking across cash, bank accounts, digital wallets, credit cards, and investments.
- **Credit Card & Installment Engine:** Specialized modeling for statement cutoffs, billing cycles, pending payment holds, and multi-month installment schedules.
- **Envelope Budgeting & Sinking Funds:** Flexible budget groups, recurring monthly allocations, savings targets, and designated set-asides.
- **Bills & Receivables:** Forward-looking cash flow tracking for upcoming recurring bills, subscriptions, and outstanding reimbursements.
- **Treasury Web Portal:** Dedicated companion Flutter Web application (`treasury_web_app`) providing a desktop-optimized command center with full-width ledger tables, budget grids, and deep reporting.

### 5. 🤖 Conversational AI Coach ("Nudgy")
- **Natural Language Quick-Logging:** Log multi-item expenses, meals, water intake, and habits through natural conversation or receipt/image snapshots.
- **Structured Tool Execution:** Nudgy queries balances, logs ledger entries, inspects budget headroom, and updates schedules via structured tool calls.
- **Daily Check-Ins & Briefings:** Context-aware morning check-ins and practical daily advice in plain, encouraging language.

### 6. ☁️ Offline-First Sync, Security & Resilience
- **Offline-First Storage:** Local persistence backed by SQLite (`sqflite`) and key-value storage for instant response times without network connectivity.
- **Realtime Cloud Synchronization:** Multi-device sync powered by Supabase with conflict resolution, Postgres RPCs, and data version guards.
- **Encrypted Local Backups:** Client-side AES-GCM encrypted backup exports (`.enc`) and cloud snapshot restoration.
- **App Lock & Privacy:** Biometric / PIN app lock protection for sensitive personal and financial data.

---

## 🎨 Design System

Nudgr uses a custom, refined design system built on **Material 3 foundation with Apple HIG sensibilities**:

- **Dual-Theme Palette:** Dark-first (near-black `#0A0A0B` / `#131315` surfaces) with a clean derived light mode (`#FFFFFF` / `#F0F0F5`).
- **Domain-Semantic Accent Hues:** Each domain carries a distinct, glanceable semantic color identity:
  - **Fasting:** Blue (`#2E90FA`)
  - **Nutrition:** Teal (`#26C6DA`)
  - **Activity (Move):** Green (`#46BD6B`)
  - **Bills:** Orange (`#FF8A4C`)
  - **Treasury:** Gold (`#FFCA28`)
  - **Weight:** Purple (`#926AFA`)
- **Strict Theme Awareness:** All UI widgets consume tokens dynamically via `Theme.of(context)` and `AppThemeExtension`; hardcoded colors in widgets are strictly prohibited.
- **Thumb Zone Ergonomics:** Critical mobile actions and navigation triggers are positioned in the bottom 30% of the screen with touch targets $\ge 44 \times 44$ pt.

---

## 🏗️ Architecture & Engineering Guardrails

The application enforces a strict **Model-View-Presenter (MVP)** architecture:

- **Models (`lib/models/`):** Immutable data transfer objects with explicit serialization (`fromJson` / `toJson`) and domain validation.
- **Views (`lib/views/`):** Declarative, dumb UI components listening to Presenters via `ListenableBuilder`. No calculations, filtering, or business logic inside `build()`.
- **Presenters (`lib/presenters/`):** State machines, domain calculations, and service orchestration. Inter-presenter wiring is centralized in explicit dependency graphs (e.g., `TreasuryPresenters`).
- **Services (`lib/services/`):** Pure I/O layers (storage abstractions, sync engine, health connect, notifications, AI API clients).

---

## 🛠 Tech Stack

| Layer | Technologies |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) (Dart 3+ with sound null safety, pattern matching & records) |
| **Platforms** | Android (Mobile App & Home Widgets), Web (Companion Treasury Portal) |
| **State Management** | MVP Pattern (`ChangeNotifier`, `ValueNotifier`, `ListenableBuilder`) |
| **Cloud & Backend** | [Supabase](https://supabase.com/) (PostgreSQL, Row Level Security, Realtime, RPCs) |
| **AI / LLM** | AWS Bedrock / Claude / Gemini API microservices with structured function calling |
| **Local Storage** | `sqflite` (SQLite), `shared_preferences`, AES-GCM file encryption |
| **Device Integration** | `flutter_local_notifications`, `home_widget`, Health Connect |

---

## 📂 Project Structure

```
lib/
├── models/         # Immutable domain models & serialization
├── presenters/     # State management & business logic
│   ├── treasury_presenters.dart  # Central dependency wiring for finance
│   ├── ai_coach_presenter.dart   # Nudgy conversational AI orchestration
│   ├── fasting_presenter.dart    # Fasting loop state machine
│   ├── nutrition_presenter.dart  # Food logging, macros & body composition
│   ├── activity_presenter.dart   # Health Connect & movement tracking
│   └── ledger_presenter.dart     # Double-entry personal finance ledger
├── views/          # Dumb UI widgets observing Presenters
│   ├── widgets/    # Reusable atomic design tokens & hub cards
│   ├── web/        # Responsive screens for Treasury Web companion
│   ├── nutrition/  # Food logging, grocery cart & weight screens
│   ├── treasury/   # Ledger, budget, accounts, bills & credit screens
│   ├── activity/   # Steps and movement tracking screens
│   └── hub_screen.dart # Central life OS dashboard
├── services/       # Atomic I/O services (Storage, Sync, Health, AI, Backup)
├── utils/          # Pure helper functions, formatters & design tokens
├── app_colors.dart # Theme color token definitions (Dark & Light)
├── main.dart       # Mobile entrypoint & dependency injection
└── main_web.dart   # Web portal entrypoint
```

---

## 📚 Technical Specifications

Core domain specifications live in the [`docs/`](docs/) directory:

- **Fasting Loop:** [`docs/fasting_loop_spec.md`](docs/fasting_loop_spec.md)
- **AI Coach & Quick-Logging:** [`docs/ai_coach_spec.md`](docs/ai_coach_spec.md), [`docs/chat_logging_coverage.md`](docs/chat_logging_coverage.md)
- **Treasury & Finance:** [`docs/expense_classification_spec.md`](docs/expense_classification_spec.md), [`docs/credit_accounts_spec.md`](docs/credit_accounts_spec.md), [`docs/treasury_web_spec.md`](docs/treasury_web_spec.md)
- **Design System:** [`docs/design_system_nudgr_spec.md`](docs/design_system_nudgr_spec.md)
- **Data Security & Backup:** [`docs/data_security_spec.md`](docs/data_security_spec.md)
- **Operational Guidelines:** [`AGENTS.md`](AGENTS.md), [`CLAUDE.md`](CLAUDE.md)

---

## 📄 License & Terms

**Proprietary — All Rights Reserved.**

This repository is maintained strictly for private personal use. It is **not** open-source software, and no permission is granted for copying, modifying, redistributing, or publishing this codebase in any form.

To report security vulnerabilities, please refer to [SECURITY.md](SECURITY.md).
