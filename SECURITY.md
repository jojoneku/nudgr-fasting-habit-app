# Security Policy

## Supported Versions

Only the latest release on the `main` branch receives security updates.

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| Older   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

Instead, report them privately using one of the following channels:

1. **GitHub Security Advisories** (preferred):
   [Open a private advisory](https://github.com/jojoneku/nudgr-fasting-habit-app/security/advisories/new)
2. **Email:** eljonblantucas@gmail.com

Please include:

- A description of the issue and its potential impact
- Steps to reproduce (proof-of-concept code, screenshots, or a minimal failing case)
- The affected version, platform (Android / iOS / Web / Windows), and Flutter version
- Any suggested mitigation, if known

You should receive an acknowledgment within **72 hours**. We aim to provide a remediation plan within **7 days** for confirmed issues.

## Scope

In scope:

- The Flutter app source in `lib/`
- CI workflows in `.github/workflows/`
- Backend integration code (Supabase, AI services)
- Dependency vulnerabilities surfaced by Dependabot

Out of scope:

- Vulnerabilities in third-party services we integrate with (report those directly to the vendor)
- Issues requiring physical access to an unlocked device
- Social engineering of maintainers or users

## Disclosure

We follow a coordinated disclosure model. After a fix is shipped, we will publish a security advisory crediting the reporter (unless anonymity is requested).
