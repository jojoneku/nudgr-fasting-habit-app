## ADDED Requirements

### Requirement: Credit cards under Accounts with quick Pay

The Dashboard SHALL be the single home for credit-card balances: the Credit section SHALL render
directly under the Accounts list and SHALL offer a quick **Pay** action per card.

#### Scenario: Credit section placement
- **WHEN** the user has one or more credit (liability) accounts
- **THEN** a "Credit" section appears immediately below the Accounts list, each card showing the amount
  owed, a utilization meter, and the due date

#### Scenario: Quick pay a card
- **WHEN** the user taps **Pay** on a credit card that has a balance
- **THEN** the shared quick-pay sheet opens; confirming records the payment (a transfer from the chosen
  funding account) and refreshes the Dashboard totals

#### Scenario: No credit accounts
- **WHEN** the user has no credit accounts
- **THEN** no Credit section is shown
