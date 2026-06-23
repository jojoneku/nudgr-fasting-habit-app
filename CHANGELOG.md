# Changelog

All notable changes to Nudgr are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

Release sections below are generated automatically from
[Conventional Commit](https://www.conventionalcommits.org) messages at release
time (`scripts/release_changelog.sh`), so the quality of an entry mirrors the
quality of its commit subject. Each released version maps to a full APK
(distributed via `manifest.json`); the Dart-only changes shipped as over-the-air
**Shorebird patches** between releases are folded into the next release's notes
automatically, since they're the same commits (see
[docs/shorebird_code_push.md](docs/shorebird_code_push.md)).

## [Unreleased]

### Added
- Shorebird code-push scaffolding: ship Dart-only fixes as small over-the-air
  patches instead of a full APK re-download. Complements the existing APK +
  `manifest.json` flow; surfaces an "Update installed — reopen to apply" nudge
  when a patch is staged.

### Fixed
- **Training Grounds:** step/distance data stopped syncing on Jun 21 after
  Health Connect relabeled the on-device source (`android` →
  `com.android.healthconnect.phone.*`). On-device labels are now merged into one
  "Phone" source (per-day max), so an OS relabel no longer drops data or splits
  history — and it self-heals against future relabels.

[Unreleased]: https://github.com/jojoneku/nudgr-fasting-habit-app/compare/v1.0.75...HEAD
