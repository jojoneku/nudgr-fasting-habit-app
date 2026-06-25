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

[Unreleased]: https://github.com/jojoneku/nudgr-fasting-habit-app/compare/v1.1.3...HEAD
[1.1.0]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.0
[1.1.1]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.1
[1.1.2]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.2
[1.1.3]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.3
