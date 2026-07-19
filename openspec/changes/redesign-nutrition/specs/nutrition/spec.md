## ADDED Requirements

### Requirement: Nutrition screen header

The Nutrition screen SHALL present a header containing the title "Nutrition", an AI-tier indicator,
and entry points to History and Library. The header MUST NOT contain business logic in `build()`;
all state comes from the presenter.

#### Scenario: Cloud AI available
- **WHEN** the screen renders and cloud AI is configured and available
- **THEN** the header shows a "Cloud" pill in the domain accent color with a cloud icon

#### Scenario: Cloud AI unavailable
- **WHEN** cloud AI is not configured or not available
- **THEN** the header shows a "Local" pill with an on-device icon

#### Scenario: Open History
- **WHEN** the user taps the history control
- **THEN** the app navigates to the nutrition history screen

#### Scenario: Open Library
- **WHEN** the user taps the library control
- **THEN** the app navigates to the food library screen

#### Scenario: Back navigation when pushed
- **WHEN** the screen was pushed onto the navigation stack (can pop)
- **THEN** a back control is shown in the header; otherwise no back control is shown

### Requirement: Date navigation

The screen SHALL let the user view any past day and today via a week strip, with the current-month
label, week previous/next arrows, and a month picker. Future days beyond today MUST NOT be
selectable.

#### Scenario: Select a day in the visible week
- **WHEN** the user taps a day chip that is today or in the past
- **THEN** the presenter's selected date updates and the hero and log reflect that day

#### Scenario: Attempt to select a future day
- **WHEN** the user taps a day chip after today
- **THEN** the selection does not change

#### Scenario: Navigate weeks
- **WHEN** the user taps the previous-week arrow
- **THEN** the strip shows the prior week; the next-week arrow is disabled when the visible week is the current week

#### Scenario: Open month picker
- **WHEN** the user taps the calendar/expand control
- **THEN** a month-picker sheet opens and choosing a date sets the selected date

### Requirement: Eaten Today hero

The screen SHALL show an "EATEN TODAY" hero card summarizing the selected day's calories and macros.
It MUST display eaten calories, calories left relative to the effective goal, a calorie progress
bar, and Protein/Carbs/Fat values each with a mini progress bar. Calories burned MUST remain
available (in the hero or its breakdown). Tapping the hero SHALL open the existing breakdown sheet.

#### Scenario: Under goal
- **WHEN** eaten calories are at or below the effective goal
- **THEN** the "left of goal" value and calorie bar use the domain accent color

#### Scenario: Over goal
- **WHEN** eaten calories exceed the effective goal
- **THEN** the calorie bar (and over-goal indicator) uses the danger color

#### Scenario: Macro mini-bars
- **WHEN** macro goals are configured
- **THEN** each of Protein/Carbs/Fat shows its gram value and a mini progress bar toward its goal

#### Scenario: Open breakdown
- **WHEN** the user taps the hero card
- **THEN** the nutrition breakdown sheet opens showing calories (with burned) and per-macro detail

### Requirement: Today's log

The logged food entries for the selected day SHALL render as structured entry cards in a single flat
list, ordered newest-first, with NO meal-slot grouping or section headers. This replaces the
chat-bubble feed. A "Today's log" section label showing the day's total calories SHALL precede the
list.

#### Scenario: Flat newest-first list
- **WHEN** the selected day has logged food entries
- **THEN** all entries appear in one list ordered newest-first, with no Breakfast/Lunch/Dinner/Snack headers

#### Scenario: Day total
- **WHEN** the log renders for a day with entries
- **THEN** the "Today's log" label shows that day's total calories

#### Scenario: Empty day
- **WHEN** the selected day has no logged entries
- **THEN** an empty state is shown ("Log food or exercise below" for today, "Nothing logged" for past days)

### Requirement: Log entry card

Each logged entry SHALL render as a card showing the item/meal name, a sub-line (amount/grams and
time), a source badge (Cloud, Local, or Library), the calorie value, and Protein/Carbs/Fat macro
dots. A newly added entry MAY be briefly emphasized.

#### Scenario: Source badge reflects estimation source
- **WHEN** an entry was estimated by cloud AI, on-device AI, or added from the library
- **THEN** the card shows the corresponding badge (Cloud / Local / Library) with its icon and color

#### Scenario: Low-confidence entry
- **WHEN** an entry is low-confidence or needs confirmation
- **THEN** the card indicates it needs review (and alternatives remain reachable via the entry menu)

### Requirement: Entry actions menu

Each entry SHALL expose an overflow (`⋯`) control that reveals Edit, Save (as template), Wrong, and
Delete actions. Destructive and log actions SHALL surface an undo affordance.

#### Scenario: Expand menu
- **WHEN** the user taps the `⋯` control on an entry
- **THEN** an action row with Edit / Save / Wrong / Delete is revealed

#### Scenario: Edit reopens composer
- **WHEN** the user taps Edit
- **THEN** the composer opens pre-filled to edit that entry, and logging replaces the entry rather than adding a new one

#### Scenario: Delete with undo
- **WHEN** the user taps Delete
- **THEN** the entry is removed and an undo toast is shown; tapping Undo restores the entry

#### Scenario: Wrong match
- **WHEN** the user taps Wrong
- **THEN** the entry is marked disliked (feeding the learning signal) and the user is acknowledged

#### Scenario: Save as template
- **WHEN** the user taps Save
- **THEN** the save-as-template sheet opens allowing the entry/meal to be saved to the library

### Requirement: Logging composer sheet

A pinned "Log a meal or exercise…" input bar SHALL be presented at the bottom of the screen; tapping
it SHALL open a composer bottom-sheet. The composer SHALL support: typing a description, showing the
draft, an "Analyzing…" state, and an estimate card with the parsed items, macro totals, and
**Log it** / **Edit** actions. Quick-add chips SHALL be offered in the compose phase.

#### Scenario: Open composer
- **WHEN** the user taps the pinned input bar
- **THEN** the composer sheet opens focused on the text input with quick-add chips visible

#### Scenario: Analyze a typed meal
- **WHEN** the user submits a meal description
- **THEN** the composer shows an analyzing state, then an estimate card with items and P/C/F/kcal totals

#### Scenario: Log the estimate
- **WHEN** the user taps "Log it" on the estimate
- **THEN** the items are logged to the selected day, the sheet closes, and an undo toast is shown

#### Scenario: Edit the estimate
- **WHEN** the user taps "Edit" on the estimate
- **THEN** the composer returns to an editable state for the items before logging

#### Scenario: Quick-add chip
- **WHEN** the user taps a quick-add chip
- **THEN** its text is submitted for analysis as if typed

#### Scenario: First-run AI not available
- **WHEN** neither cloud nor on-device AI is available and the cool-down has not been skipped
- **THEN** opening the composer first presents the "Set up smart logging" prompt

### Requirement: Photo logging

The user SHALL be able to log a meal from a photo via a source → preview → estimate sheet sequence.
Photo-sourced entries MUST be attributed to the photo/AI source and MUST NOT auto-learn into the
personal dictionary.

#### Scenario: Choose a photo source
- **WHEN** the user starts photo logging
- **THEN** a sheet offers "Take photo" and "Choose from gallery"

#### Scenario: Preview and analyze
- **WHEN** a photo is captured or picked
- **THEN** a preview with an optional note and Retake / Analyze actions is shown

#### Scenario: Photo estimate
- **WHEN** analysis completes
- **THEN** an estimate sheet lists detected items with macro totals and Log it / Edit actions

### Requirement: Exercise entries

Exercise logged through the composer SHALL be recorded and rendered as a log entry showing the
activity name, its stats, and calories burned (as a subtraction), distinct from food entries.

#### Scenario: Log exercise
- **WHEN** the user submits an exercise description and logs it
- **THEN** an exercise entry appears in the day's log showing burned calories, and the hero's burned value updates

### Requirement: First-run AI setup prompt

When smart logging has no AI backend available, the screen SHALL offer a first-run prompt to set up
on-device or cloud AI, styled per the reference, with a skip option honoring a cool-down.

#### Scenario: Download on-device AI
- **WHEN** the user chooses "Download AI"
- **THEN** the on-device model download starts and the cool-down resets on completion

#### Scenario: Skip for now
- **WHEN** the user chooses "Skip for now"
- **THEN** the prompt dismisses and is not shown again within the cool-down window

### Requirement: Loading and error states

The screen SHALL communicate analysis progress and failures without blocking the rest of the UI.

#### Scenario: Analysis in progress
- **WHEN** a meal is being analyzed
- **THEN** an analyzing indicator is shown in the composer

#### Scenario: Analysis error
- **WHEN** analysis fails
- **THEN** an error message is shown and the user can retry or edit the input

### Requirement: Graceful degradation without AI coach

The screen SHALL render and remain usable when the optional AI-coach presenter is absent.

#### Scenario: No AI-coach presenter
- **WHEN** the screen is constructed without an AI-coach presenter
- **THEN** the header, hero, log, and manual logging still function and no crash occurs

### Requirement: Theme and iconography conformance

All screen widgets SHALL read colors from `Theme.of(context)` / `context.appColors` and MUST NOT
hardcode `AppColors`/`AppColorsLight` tokens. Icons SHALL use Material icons. The screen MUST render
correctly in both dark and light themes.

#### Scenario: Light theme
- **WHEN** the app is in light theme
- **THEN** the hero, log cards, badges, and composer use theme-derived colors with adequate contrast

#### Scenario: Dark theme
- **WHEN** the app is in dark theme
- **THEN** the screen matches the Nudgr dark reference using theme tokens (no hardcoded per-mode tokens)
