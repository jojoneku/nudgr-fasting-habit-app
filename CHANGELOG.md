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

## [1.1.59] - 2026-08-05

### Added
- let a paid, received, or funded entry be undone

### Fixed
- accept an int amount when clearing a settlement field

## [1.1.58] - 2026-08-04

### Added
- drag-to-rearrange receivables, stable category colors
- jump-to-newest button; fix stolen scroll, copy, and title

### Fixed
- a bill payable FROM a card no longer blocks its statement
- bill the closing balance, stop silent statement deletes, surface the cycle
- stop a filed statement from shutting the auto-statement window

## [1.1.57] - 2026-07-30

### Added
- add an "All accounts" dialog to the dashboard

### Fixed
- drop the service worker and retire the ones already registered
- page finance pulls; enable the cloud tier on web

## [1.1.56] - 2026-07-30

### Added
- Money Mentor dock and receipt scanning on the Treasury web app
- port the mobile Nudgr skin to the Treasury web companion

### Fixed
- size un-quantified dishes as servings, not as pieces
- honour stated weights in multi-item food logs
- stop the receipt drop target stranding its highlight
- defects found by rendering the app, not just testing it
- mobile month-end outlook mirrors the web decomposition

## [1.1.55] - 2026-07-26

### Added
- add Goals & Savings as its own tab
- add custom foods to personal dictionary

### Fixed
- refresh Hub steps from Health Connect on launch and resume
- repeat-learning fills My Foods without Cloud AI

## [1.1.54] - 2026-07-23

### Added
- scan receipts to log expenses from a photo

### Fixed
- stop routing bare numbers into the expense-log pipeline
- stop action sheet grey-screen when opening month picker

## [1.1.53] - 2026-07-23

### Added
- browsable saved conversations (ChatGPT-style history)
- photo upload + word-cycling "thinking" status
- project goals forward via their monthly savings plan
- itemize bills/receivables/set-asides for present + past too
- give Money Mentor itemized future obligations for planning

### Fixed
- add missing adviseFinance override to generated advisor mock

## [1.1.52] - 2026-07-23

### Added
- add recent transactions + credit APR/utilization to snapshot
- add spending pace, net-worth momentum & maturity analytics
- give Money Mentor goals, per-account cash, budgets & installments
- fix Money Mentor formatting and give it full financial picture

## [1.1.51] - 2026-07-22

### Added
- cross-device sync via SyncDomain.advisorState (LWW)
- in-chat expense logging with a polished confirm card
- memory view for user-curated goals/risk/notes
- local persistence for chat history + user-curated profile
- dual-mode hub bar — open the financial advisor from the quick-log bar
- backend op + service/context/presenter core for AI financial advisor

### Fixed
- make the daily nudge tone plain, not RPG/gamey

## [1.1.50] - 2026-07-22

### Fixed
- reopen camera/gallery from the composer photo button

## [1.1.49] - 2026-07-21

### Added
- compact macro row + derive macro targets from calorie goal
- History overview + lighter live tiles
- spending range selector; drop duplicate ledger totals
- calculator amount + hero layout on Log Transaction
- rework Budget tab — hide app bar, restructure card, txn popup
- new-entry type picker as a segmented control
- redress bills mark/confirm sheets to shared chrome
- redesign the Set/Edit Budget sheet to the Nudgr field language
- reskin Add/Edit Transaction sheet to the reference
- consolidate bill forms — graft reference account picker
- combined bill/receivable entry + kit restyle of both forms
- migrate add-account form to the form kit
- migrate add-installment + add-transaction to the form kit
- implement redesign-bills-forms (unified sheet + reminder)
- migrate expense + installment mark-as-paid to the form kit
- add Nudgr form kit + migrate mark-as-paid (bill, received)
- restore card detail on the Bills obligation cards
- show remaining in ring hero, simplify month switcher
- name-monogram fallback for category badges
- redesign Budget tab as per-budget cards
- restructure the Bills tab (redesign-bills-page)
- hide module app bar on Ledger tab (title owns the top)
- redesign Ledger page (reskin + superset)
- choosable account icons + brand monograms
- month-grid popover picker (drop header chevrons)
- month/year switcher + move day filter into Filter & sort
- month/year switcher + move day filter into Filter & sort
- quick-clear (X) button on Ledger Filter & sort bar
- unified Ledger filter & sort (multi-select + ordering)
- photo estimate review before logging
- reference field-boxes in Account Setup, Categories, Budget Groups (7-10/10)
- reference field-boxes in Add/Edit Transaction (6/10)
- reference field-boxes in Add Bill + Add Receivable (4-5/10)
- reference field-boxes in Bills sheets (3/10)
- reference field-boxes in Add Installment (2/10)
- reference sheet field-boxes — shared helper + Add Budget (1/10)
- dedicated Goals & Savings screen (Nudgr redesign)
- List/Calendar view toggle in Ledger (Nudgr redesign)
- budget progress bar in Cart header (Nudgr redesign)
- reference month pill in Bills (Nudgr redesign)
- reference input pill + month pill in Ledger (Nudgr redesign)
- composer draft bubble, persistent input, log undo
- review estimate before logging (composer)
- blue estimate accent in Cart (Nudgr redesign, increment 6)
- per-month savings rate in History (Nudgr redesign, increment 5)
- pace-aware budget hero (Nudgr redesign, increment 4)
- DUE SOON bills hero (Nudgr redesign, increment 3)
- full "Save as template" sheet
- category-specific ledger icons (Nudgr redesign, increment 2)
- add delete-undo for Today's log entries
- Nudgr dashboard redesign — hero, cashflow strip, accounts (increment 1)
- Nudgr redesign — flat log list, composer sheet, photo restyle
- add EATEN TODAY hero (Nudgr redesign, increment 1)

### Fixed
- don't silently drop a log when the eating window closes
- make log-card menu tap target a full 44x44
- monthly detail uses category/account icon badges
- enable mouse/trackpad drag so PageViews swipe on web/desktop
- reskin monthly detail page
- reskin History tab — compact month cards, in-page title
- hide OTHER type badge on bill/receivable rows
- full-width due-soon card
- budget card — progress bar under name, drop txn popup
- form consistency — segment height, category picker, notes, installment
- budget card — full-width progress, drop txn count, tap hint
- shorten the new-entry type segmented control
- label the receivable Date picker so it aligns with Amount
- align manage-categories row + numbers to Jakarta Sans
- make month-year picker sheet scrollable (pre-existing overflow)
- stamp category updatedAt on add/update (sync correctness)
- a11y double-read, monogram emoji-names, add-preview color
- ring hero "remaining" reads "over" for zero-allocation spend
- restore budget-card parity dropped in the redesign
- restore account color dot; live category-icon preview
- guard Ledger controls-row overflow; test resolveCategoryIcon
- always show Accounts + Categories in Ledger filter sheet
- address review findings on the estimate flow

## [1.1.48] - 2026-07-19

- Maintenance and internal improvements.

## [1.1.47] - 2026-07-16

### Fixed
- restore weight-log screen access from the weight tile

## [1.1.46] - 2026-07-16

### Fixed
- stop hero ring glow from being sheared by the pinned app bar

## [1.1.45] - 2026-07-16

### Added
- download and install updates in-app instead of via browser

### Fixed
- replace open_file_plus with open_filex to fix release build
- resolve undefined UpdateManifest type in update prompt

## [1.1.44] - 2026-07-15

### Fixed
- file credit statements under their real due month
- persist hub module order across app restarts
- report cloud coach failures accurately, never as insights

## [1.1.43] - 2026-07-13

### Added
- hub coach line rework, daily brief sheet, app wiring (plan 057 phase 4)
- add InsightsPresenter engine (plan 057 phase 3)
- add insight persistence to StorageService (plan 057 phase 2)
- add snapshot/insight models and pure utils (plan 057 phase 1)

### Fixed
- guard brief generation and refresh against re-entrancy

## [1.1.42] - 2026-07-12

### Fixed
- show paid/received items as deactivated, not just struck out
- make quest "Mark as Done" action actually complete
- per-quest check on Quests card instead of one ambiguous button

## [1.1.41] - 2026-07-12

- Maintenance and internal improvements.

## [1.1.40] - 2026-07-12

### Added
- ring hero, coaching line, rich Finance card + micro-actions

## [1.1.39] - 2026-07-11

### Fixed
- stop promotion PRs merging before required checks register

## [1.1.38] - 2026-07-11

### Added
- per-step skip, review step, plain copy + lighter accents
- first-run Awakening wizard (Nudgr)

## [1.1.37] - 2026-07-11

### Added
- unify Treasury web companion onto Nudgr tokens
- adopt Nudgr dark-first token system + on-brand charts

## [1.1.36] - 2026-07-06

### Added
- set-aside funding accounts, by-account breakdown & transfers

## [1.1.35] - 2026-07-06

### Fixed
- allow changing a reimbursable expense's expected payback date

## [1.1.34] - 2026-07-04

### Added
- balance dashboard content cards with a masonry layout

## [1.1.33] - 2026-07-04

### Added
- show account balances as cards below the Month-End Outlook

### Fixed
- clarify Proj. Month-End Cash subtitle includes budget

## [1.1.32] - 2026-07-04

### Added
- replace duplicate Current Obligations tile with Budget Allocated

### Fixed
- stop farmable XP via a persisted one-time-award guard
- only net linked custodian balances out of dashboard KPIs
- clear category on inline type flip; require category on draft add
- guard day rollover and reset streak on a missed day
- make credit-card statement bills payable on web
- stop mobile account edit from orphaning sub-account pockets
- stop logging JWT + PII; fail rate limiter closed
- diff-based dirty marking to stop cross-device data loss

## [1.1.31] - 2026-07-04

### Added
- recurring set-asides, unpaid-first ordering, side-by-side bills

## [1.1.30] - 2026-07-04

- Maintenance and internal improvements.

## [1.1.29] - 2026-07-04

### Added
- add notification action buttons (Done / Snooze / Skip)

### Fixed
- stop credit-card statements proliferating into future months

## [1.1.28] - 2026-06-30

### Added
- per-category exclude-from-totals toggle

## [1.1.27] - 2026-06-30

### Added
- full-peso account balances and sorted bill lists

### Fixed
- hide raw __auto_statement__ marker from the UI

## [1.1.26] - 2026-06-30

### Fixed
- make home-screen widgets fill their card and never render blank

## [1.1.25] - 2026-06-29

### Fixed
- stack bills & receivables on mobile, keep side-by-side web-only

## [1.1.24] - 2026-06-28

### Added
- show both accounts on a transfer row in the web ledger

## [1.1.23] - 2026-06-28

### Added
- surface credit-card intelligence on the web dashboard
- installments section on the web bills page
- create nested sub-accounts (pockets/goals/time deposits)
- create savings/goal budgets on the web budget page

### Fixed
- snap to current month on chat-commit; don't wipe cart budget on bad input
- budget total reconciles with rows + cap setBudget XP
- account integrity — ledger sync, dropdown crash, icon, errors
- keep reimbursement receivables in sync on edit & undo

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

[Unreleased]: https://github.com/jojoneku/nudgr-fasting-habit-app/compare/v1.1.59...HEAD
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
[1.1.23]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.23
[1.1.24]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.24
[1.1.25]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.25
[1.1.26]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.26
[1.1.27]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.27
[1.1.28]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.28
[1.1.29]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.29
[1.1.30]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.30
[1.1.31]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.31
[1.1.32]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.32
[1.1.33]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.33
[1.1.34]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.34
[1.1.35]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.35
[1.1.36]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.36
[1.1.37]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.37
[1.1.38]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.38
[1.1.39]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.39
[1.1.40]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.40
[1.1.41]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.41
[1.1.42]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.42
[1.1.43]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.43
[1.1.44]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.44
[1.1.45]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.45
[1.1.46]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.46
[1.1.47]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.47
[1.1.48]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.48
[1.1.49]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.49
[1.1.50]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.50
[1.1.51]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.51
[1.1.52]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.52
[1.1.53]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.53
[1.1.54]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.54
[1.1.55]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.55
[1.1.56]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.56
[1.1.57]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.57
[1.1.58]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.58
[1.1.59]: https://github.com/jojoneku/nudgr-fasting-habit-app/releases/tag/v1.1.59
