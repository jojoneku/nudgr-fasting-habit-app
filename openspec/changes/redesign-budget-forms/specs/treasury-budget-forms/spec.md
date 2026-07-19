## ADDED Requirements

### Requirement: Set / Edit Budget sheet in the Nudgr field language
The Set / Edit Budget sheet SHALL use the shared sheet-field language: uppercase field labels over
bordered field boxes, a target picker box, an emphasized ₱ amount field, and group/type selectors —
matching the Bills forms. It MUST preserve every field and behavior of the prior sheet (target
selection, amount, budget group, budget type, save, and remove) and introduce no new persistence.

#### Scenario: Reference-styled fields
- **WHEN** the Set Budget sheet opens
- **THEN** each field shows an uppercase label above a bordered box, the amount box is emphasized with a
  ₱ prefix, and group/type render as segmented selectors

#### Scenario: Field and behavior parity
- **WHEN** a budget is set or edited through the redesigned sheet
- **THEN** it saves with the same category/account, amount, group, and type semantics as before

### Requirement: Target picker with create-category
Selecting the budgeted target SHALL use a tappable picker box that opens a bottom-sheet list. In expense
mode the list MUST include a "New category" action that runs the create-category flow and selects the
new category; in savings mode it MUST list the savings / goal accounts.

#### Scenario: Pick an existing category
- **WHEN** the user opens the picker and taps a category
- **THEN** that category becomes the budget target and its name shows in the picker box

#### Scenario: Create a category from the picker
- **WHEN** the user chooses "New category" and enters a name
- **THEN** the category is created, selected as the target, and shown in the picker box

#### Scenario: Savings group lists accounts
- **WHEN** the budget group is Savings
- **THEN** the picker lists savings / goal accounts instead of expense categories

### Requirement: Group switch resets an incompatible target
Switching the budget group between an expense group and the savings group SHALL clear the selected
target, because expense categories and savings accounts occupy the same target slot but come from
different lists.

#### Scenario: Crossing expense ↔ savings clears the target
- **WHEN** the user changes the group from an expense group to Savings (or vice versa)
- **THEN** the previously selected target is cleared so an incompatible id cannot be saved

### Requirement: Edit-from-card shows a locked target
When the sheet is opened for an existing budget from its card (preselected target), the target SHALL be
shown in a read-only box rather than an editable picker.

#### Scenario: Preselected target is read-only
- **WHEN** the sheet opens with a preselected target
- **THEN** the target is displayed in a non-editable box while amount, group, and type remain editable
