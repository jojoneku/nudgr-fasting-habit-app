# Changelog

All notable changes to Nudgr are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

Release sections below are generated automatically from
[Conventional Commit](https://www.conventionalcommits.org) messages at release
time (`scripts/release_changelog.sh`), so the quality of an entry mirrors the
quality of its commit subject. Each released version maps to a full APK
distributed via `manifest.json`.

## [Unreleased]

## [1.1.12] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- switch Firebase deploy to Workload Identity Federation
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.11] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.10] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- use google-github-actions/auth@v2 for Firebase credential setup
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.9] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.8] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- write SA JSON via printf+env-var to avoid shell quoting issues
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.7] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- authenticate Firebase deploy via GOOGLE_APPLICATION_CREDENTIALS
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.6] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- replace broken action-hosting-deploy with direct firebase deploy
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.5] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- use correct Firebase service account secret name
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.4] - 2026-06-25

### Added
- move owed-to-you filter into the category picker
- add quick-log chat to the Finance card
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- source "owed to you" from receivable state, not inflow legs
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.3] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- resolve device timezone via TimezoneInfo.identifier
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.2] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data
- stop budget alert re-fire race + stale Strava data on resume

## [1.1.1] - 2026-06-25

### Added
- reimbursable follow-ups — owedBy, re-sync, owed filter, NLP
- NLP routing for paid-on-card-for-someone (Phase E)
- reimbursable toggle + paid-for-someone intent (Phase C/D)
- reimbursable expense model + budget exclusion (Phase A/B)
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- accept currency markers after the amount in chat parser
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.0] - 2026-06-23

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

[Unreleased]: https://github.com/jojoneku/nudgr-fasting-habit-app/compare/v1.1.12...HEAD
[1.1.0]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.0
[1.1.1]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.1
[1.1.2]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.2
[1.1.3]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.3
[1.1.4]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.4
[1.1.5]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.5
[1.1.6]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.6
[1.1.7]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.7
[1.1.8]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.8
[1.1.9]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.9
[1.1.10]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.10
[1.1.11]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.11
[1.1.12]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.12
