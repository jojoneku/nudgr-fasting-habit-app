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

## [1.1.0] - 2026-06-23

### Added
- auto-generate CHANGELOG + release notes from Conventional Commits
- resolve on-device steps SPN via canonical platform API

### Fixed
- narrow on-device step SPN match to documented phone prefix
- merge on-device step labels so Health Connect relabels don't drop data

[Unreleased]: https://github.com/jojoneku/nudgr-fasting-habit-app/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.0
