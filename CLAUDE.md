# The System — Intermittent Fasting App (CLAUDE.md)

Claude acts as the **System Architect** for this Flutter project. Full philosophy, design tokens, and architecture rules are in [.github/copilot-instructions.md](.github/copilot-instructions.md).

## Project Identity
- **App:** Gamified intermittent fasting app — *Solo Leveling* RPG aesthetic
- **Stack:** Flutter (Dart 3+), MVP architecture, `ChangeNotifier` state
- **Persistence:** `StorageService` abstract interface (SharedPreferences impl)
- **Notifications:** `flutter_local_notifications` with alarm clock mode

## Architecture at a Glance
| Layer | Path | Responsibility |
|---|---|---|
| Model | `lib/models/` | Immutable data, `fromJson`/`toJson`, validation only |
| View | `lib/views/` | Dumb UI, `ListenableBuilder`, no logic |
| Presenter | `lib/presenters/` | All state, business logic, RPG math |
| Service | `lib/services/` | I/O (storage, notifications) |
| Utils | `lib/utils/` | Pure functions, no state |

## Active Specs
- [docs/fasting_loop_spec.md](docs/fasting_loop_spec.md) — Core fasting timer loop
- [docs/stats_spec.md](docs/stats_spec.md) — RPG stats & leveling system

## Non-Negotiable Rules
1. Never put calculations or conditionals in `build()` — delegate to `presenter.someGetter`
2. All persistence through `StorageService` abstract interface
3. RPG math (XP, levels, streaks) lives only in Presenters
4. Touch targets ≥ 44×44px; primary actions in bottom 30% of screen
5. Animations: 150–300ms micro-interactions, ≤ 400ms max
6. Constructor injection only — no `GetIt` or global locators

## Skills
| Skill | Description |
|---|---|
| `/feature` | Implement a feature via the SDD workflow |
| `/spec` | Create or update a feature spec in `docs/` |
| `/review` | Review code against architecture and UX rules |
| `/plan` | Generate a step-by-step implementation plan |
| `/ui-ux-pro-max` | UI/UX design intelligence — styles, colors, fonts, UX guidelines, Flutter patterns |
| `/git-workflow` | Branching strategy, Conventional Commits, PR creation, merge, conflict resolution |
| `/github-pr-review` | Review PRs via gh CLI — pending reviews, code suggestions, approval workflow |

Skills live in `.claude/skills/` — each is a directory with a `SKILL.md` entrypoint.

## Agents
| Agent | Trigger | Role |
|---|---|---|
| `architect` | Planning, design decisions | High-level design, API definition, spec authoring |
| `builder` | Coding tasks | Feature implementation following SDD |
| `reviewer` | PR / code review | Architecture compliance, UX audit |

## Plans
Plan templates live in `.claude/plans/`. Use `/plan` to generate a plan before implementing any non-trivial feature.
