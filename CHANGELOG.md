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

## [1.1.22] - 2026-06-27

### Added
- credit card live balance section + quick pay
- show bills and receivables cards side by side
- custom group CRUD + fix budget health spending zeros

### Fixed
- declare missing _selectedCategoryId field in _AddRowState
- re-run credit statement detection on month change

## [1.1.21] - 2026-06-27

### Added
- recurring receivables in the web bills page

### Fixed
- pick an existing category for budgets instead of free-text

## [1.1.20] - 2026-06-27

### Added
- exclude reimbursables/loans from income & expense everywhere
- add reimbursable / "I'll get this back" to the web ledger
- optional payback date controls which month it shows
- treat money you'll get back as not-spending

### Fixed
- scope summary repair to transfer/reimbursable months
- lift the chat bar above the keyboard
- file reimbursement/loan receivable in the month it arose
- make the finance card fully tappable

## [1.1.19] - 2026-06-27

### Added
- unified quick-log bar routes finance + nutrition

## [1.1.18] - 2026-06-27

### Added
- replace bottom FAB with a docked AI Coach chat bar
- track monthly savings contributions into pockets

### Fixed
- allow editing transfers in the web ledger

## [1.1.17] - 2026-06-26

### Added
- add data-security plan and disable Android cloud auto-backup

## [1.1.16] - 2026-06-26

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- make Firebase web deploy actually deploy (Node 20 + unmask)
- guard nutrition push against clobbering cloud feed
- stop empty cloud snapshot from wiping the local food feed
- surface logged food that has no chat row
- add missing if-guard to changelog step; restore fetch-depth for changelog diff
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.15] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.14] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- authenticate firebase-tools via SA credentials_json (WIF unsupported by firebase-tools)
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

## [1.1.13] - 2026-06-25

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- pass WIF access token to firebase-tools via GOOGLE_OAUTH_ACCESS_TOKEN
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

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

[Unreleased]: https://github.com/jojoneku/nudgr-fasting-habit-app/compare/v1.1.22...HEAD
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
[1.1.13]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.13
[1.1.14]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.14
[1.1.15]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.15
[1.1.16]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.16
[1.1.17]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.17
[1.1.18]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.18
[1.1.19]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.19
[1.1.20]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.20
[1.1.21]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.21
[1.1.22]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.22
