# Contributing to The System

Thanks for your interest in contributing! This project is a gamified intermittent fasting app built with Flutter, and we welcome bug reports, feature ideas, and pull requests.

## License Notice

This project is **All Rights Reserved** (see [LICENSE](LICENSE)). It is published for transparency and review, **not** for redistribution or independent use.

By submitting a pull request, you agree that your contribution is granted to the project owner under a perpetual, worldwide, royalty-free license to use, modify, and incorporate it into this project. If you are not comfortable with this, please do not submit code.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Getting Started

1. **Prerequisites**
   - Flutter SDK `>=3.4.1 <4.0.0`
   - Dart 3+
   - Android Studio or VS Code with the Flutter plugin

2. **Setup**
   ```bash
   git clone https://github.com/<your-username>/nudgr-fasting-habit-app.git
   cd intermittent_fasting_2
   cp .env.example .env   # then fill in your own keys
   flutter pub get
   flutter run
   ```

3. **Verify your environment**
   ```bash
   flutter analyze
   flutter test
   dart format --set-exit-if-changed .
   ```

## Branching Strategy

- `main` — protected, release-ready
- `dev` — integration branch
- Feature branches: `feat/<short-description>`
- Bug fixes: `fix/<short-description>`
- Chores / tooling: `chore/<short-description>`

Open PRs against `dev`, not `main`.

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body — explain *why*, not *what*>
```

Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `perf`.

Example:
```
feat(stats): add SEN attribute multiplier to mindfulness quests

Mindfulness quests previously awarded flat XP regardless of SEN.
Scales XP by (1 + SEN * 0.05) to reward investment in the stat.
```

## Architecture Rules (Non-Negotiable)

This codebase follows strict MVP. Before opening a PR, please verify:

1. No calculations or conditionals in `build()` — delegate to `presenter.someGetter`
2. Persistence goes through the `StorageService` abstract interface
3. RPG math (XP, levels, streaks) lives **only** in Presenters
4. Touch targets are ≥ 44×44px; primary actions in the bottom 30% of screen
5. Animations: 150–300ms for micro-interactions, ≤ 400ms max
6. Constructor injection only — no `GetIt` or global locators
7. **Theme-aware colors only** — read from `Theme.of(context)`. Do not hardcode `AppColors.X` or `AppColorsLight.X` inside widgets

Full philosophy lives in [`.github/copilot-instructions.md`](.github/copilot-instructions.md).

## Pull Request Checklist

Before requesting review:

- [ ] `flutter analyze` passes with no warnings
- [ ] `flutter test` passes
- [ ] `dart format` has been run
- [ ] New behavior has tests (unit or widget tests)
- [ ] If UI changes: screenshots in **both** light and dark mode
- [ ] No hardcoded color tokens in widgets
- [ ] Commit messages follow Conventional Commits
- [ ] PR title is clear and under 70 characters
- [ ] PR description explains the *why*

## Testing

- **Unit tests** — `test/`, isolated per layer (Model / Presenter / Service)
- **Widget tests** — `test/views/`, golden tests for critical UI
- **Integration tests** — `integration_test/`, full-flow scenarios

When mocking, prefer real fakes over `mockito` mocks for `StorageService`. See `test/fakes/` for examples.

## Reporting Bugs

Open a [bug report](https://github.com/jojoneku/nudgr-fasting-habit-app/issues/new?template=bug_report.yml). Please include device, OS version, Flutter version, and reproduction steps.

## Reporting Security Issues

**Do not** open a public issue for security vulnerabilities. See [SECURITY.md](SECURITY.md).

## Questions?

Open a [GitHub Discussion](https://github.com/jojoneku/nudgr-fasting-habit-app/discussions) (if enabled) or a regular issue tagged `question`.
