# Plan 004a — Treasury Module: Foundation
**Status:** DRAFT v2 — Awaiting Approval (updated: sub-accounts, no seeding)
**Phase:** 1 of 3
**Depends on:** Plan 001 (Nav Hub) approved and merged

---

## Goal

Establish the complete data layer for the **Treasury** financial tracker module — models, storage keys, and service methods. This is pure data architecture with no UI. Getting the schema right here avoids painful migrations later. All subsequent phases (004b, 004c) depend on this foundation.

No RPG XP/stats wired yet — that comes in Phase 2.

---

## Domain Overview

The financial tracker mirrors a personal accounting system with 5 concerns:

| Concern | Description |
|---|---|
| **Accounts** | Bank, e-wallet, cash, savings, emergency fund accounts |
| **Transactions** | The ledger — every inflow/outflow/transfer, categorized |
| **Bills & Receivables** | Monthly obligations and expected income |
| **Budget** | Category spending limits per month |
| **Budgeted Expenses** | Named spending buckets (e.g. "Family Allowance") |

A `MonthlySummary` snapshot is computed and frozen at month close for the History screen.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/finance/financial_account.dart` | Create | Model |
| `lib/models/finance/transaction.dart` | Create | Model |
| `lib/models/finance/category.dart` | Create | Model |
| `lib/models/finance/budget.dart` | Create | Model |
| `lib/models/finance/bill.dart` | Create | Model |
| `lib/models/finance/receivable.dart` | Create | Model |
| `lib/models/finance/budgeted_expense.dart` | Create | Model |
| `lib/models/finance/monthly_summary.dart` | Create | Model |
| `lib/services/storage_service.dart` | Modify | Service |

---

## Interface Definitions

### Models

```dart
// --- Enums ---

// Account categories — covers the full Philippine banking/fintech landscape.
// No institution names are ever hardcoded. Users name their own accounts.
//
// PH structural patterns this model supports:
//   1. Single flat account      → Komo, MariBank, GrabPay, traditional banks
//   2. Main + goal pockets      → GoTyme (Go Save), Tonik (Stashes), Maya (Personal Goals)
//                                  parentAccountId links each pocket to its parent
//   3. Main wallet + products   → GCash (GSave, GFunds, GCredit), Maya (Wallet + Bank)
//                                  each product is a separate FinancialAccount
//   4. Traditional multi-acct   → BPI, BDO — each product is its own account
//   5. Credit-only              → BNPL (SPayLater, BillEase) — balance = outstanding debt
//
// Top-level (parentAccountId == null):
//   bank, ewallet, cash, creditCard, creditLine, bnpl, investment
// Sub-account (parentAccountId != null):
//   savings, goal, timeDeposit, investment (can also be a top-level product)
//
// Liability types (balance = what you owe, not what you have):
//   creditCard, creditLine, bnpl
enum AccountCategory {
  // Liquid / asset accounts
  bank, ewallet, cash,
  // Locked / sub-accounts (ring-fenced pockets)
  savings, goal, timeDeposit,
  // Liability accounts — balance represents debt owed
  creditCard, creditLine, bnpl,
  // Non-liquid asset accounts
  investment,
}

// Bill types visible in the sheet
enum BillType { installment, creditCard, subscription, insurance, govtContribution, utility, other }

// Receivable source types
enum ReceivableType { salary, reimbursement, business, other }

// Budget group — maps to the 3 sections in the Budget sheet
enum BudgetGroup { nonNegotiables, livingExpense, variableOptional }

// Budget type — affects styling and calculation logic
enum BudgetType { monthly, fixed, goal, variable }

enum TransactionType { inflow, outflow, transfer }
enum CategoryType { income, expense }
enum RecurrenceType { monthly, weekly, yearly, custom }

// --- FinancialAccount ---
// Supports both main accounts and sub-accounts (savings pots, goals, time deposits)
//
// Main account:  parentAccountId == null, category ∈ {bank, ewallet, cash}
// Sub-account:   parentAccountId != null, category ∈ {savings, goal, timeDeposit}
//
// Example tree:
//   Maya (ewallet)
//   ├── Maya Savings (savings)
//   ├── Braces Fund (goal, goalTarget: 50000)
//   └── Time Deposit Jan (timeDeposit, maturityDate: 2026-06-01)
class FinancialAccount {
  final String id;
  final String name;
  final AccountCategory category;
  final String? parentAccountId;   // null = top-level account
  final double balance;            // current balance (user-maintained)
  final String currency;           // default 'PHP'
  final String colorHex;
  final String icon;               // MDI icon name
  final bool isActive;
  final double? goalTarget;        // only used when category == goal
  final DateTime? maturityDate;    // only used when category == timeDeposit

  // Derived helpers (computed, not stored):
  // bool get isSubAccount  => parentAccountId != null
  // bool get isLiquid      => category ∈ {bank, ewallet, cash}     → counts toward Total Cash
  // bool get isLocked      => category ∈ {savings, goal, timeDeposit, investment}
  // bool get isLiability   => category ∈ {creditCard, creditLine, bnpl}  → balance = debt owed

  // fromJson / toJson
}

// --- TransactionRecord ---
// Named TransactionRecord to avoid collision with Dart's Transaction
class TransactionRecord {
  final String id;
  final DateTime date;
  final String accountId;
  final String categoryId;
  final double amount;             // always positive
  final TransactionType type;
  final String description;
  final String? note;
  final String month;              // 'YYYY-MM' for filtering
  final String? billId;           // links to Bill
  final String? receivableId;     // links to Receivable
  final String? transferToAccountId; // outbound leg of transfer
  final String? transferGroupId;  // shared by both legs of a transfer pair

  // fromJson / toJson
}

// --- Category ---
// No default seeding — users create all categories themselves
class FinanceCategory {
  final String id;
  final String name;
  final CategoryType type;
  final String icon;
  final String colorHex;

  // fromJson / toJson
}

// --- Budget ---
// One row per category per month, grouped into 3 budget sections
class Budget {
  final String id;
  final String categoryId;
  final String month;            // 'YYYY-MM'
  final double allocatedAmount;
  final BudgetGroup group;       // NonNegotiables | LivingExpense | VariableOptional
  final BudgetType budgetType;   // Monthly | Fixed | Goal | Variable

  // fromJson / toJson
}

// --- BudgetedExpense ---
// Planned spending commitments (Family Support, Braces Sinking Fund, EF top-up)
// These appear in Bills & Receivables sheet under "BUDGETED EXPENSE"
class BudgetedExpense {
  final String id;
  final String name;
  final BillType budgetedType;   // reuse BillType or use ReceivableType — TBD
  final String month;            // 'YYYY-MM'
  final double allocatedAmount;
  final double? nextMonthAmount; // pre-set amount for the following month
  final double spentAmount;      // actual expense recorded
  final String categoryId;
  final String? note;            // e.g. "Cash", "Maya Savings"
  final bool isPaid;
  final String? transactionId;   // linked TransactionRecord

  // fromJson / toJson
}

// --- Bill ---
class Bill {
  final String id;
  final String name;
  final BillType billType;       // Installment, CreditCard, Subscription, etc.
  final double amount;
  final double? nextMonthAmount; // pre-set amount for the following month
  final int dueDay;              // 1–31 day of month
  final String month;            // 'YYYY-MM'
  final String categoryId;
  final String? accountId;       // preferred payment account
  final String? paymentNote;     // e.g. "Gcash 120263075639" — account/ref note
  final bool isRecurring;
  final RecurrenceType? recurrenceType;
  final bool isPaid;
  final DateTime? paidDate;
  final double? paidAmount;      // may differ from billed amount (partial pay)
  final String? transactionId;   // linked TransactionRecord

  // fromJson / toJson
}

// --- Receivable ---
class Receivable {
  final String id;
  final String name;
  final ReceivableType receivableType; // Salary, Reimbursement, Business, Other
  final double amount;
  final double? nextMonthAmount;       // pre-set amount for the following month
  final DateTime expectedDate;
  final String month;                  // 'YYYY-MM'
  final String categoryId;
  final bool isRecurring;
  final RecurrenceType? recurrenceType;
  final bool isReceived;
  final DateTime? receivedDate;
  final double? receivedAmount;        // may differ from expected
  final String? transactionId;         // linked TransactionRecord

  // fromJson / toJson
}

// --- MonthlySummary (frozen snapshot) ---
class MonthlySummary {
  final String month; // 'YYYY-MM'
  final double totalInflow;
  final double totalOutflow;
  final double totalBills;
  final double totalBillsPaid;
  final int billCount;
  final int billsPaidCount;
  final double totalReceivables;
  final double totalReceived;
  final int receivableCount;
  final double netSavings;       // inflow - outflow
  final double endingCash;       // sum of all account balances at close
  final Map<String, double> accountSnapshots;  // accountId -> balance
  final Map<String, double> categorySpend;     // categoryId -> total spent

  // fromJson / toJson
}
```

### StorageService New Keys & Methods

```dart
// Keys (static const strings on StorageService)
static const keyFinancialAccounts    = 'finance_accounts';
static const keyTransactions         = 'finance_transactions';
static const keyFinanceCategories    = 'finance_categories';
static const keyBudgets              = 'finance_budgets';
static const keyBudgetedExpenses     = 'finance_budgeted_expenses';
static const keyBills                = 'finance_bills';
static const keyReceivables          = 'finance_receivables';
static const keyMonthlySummaries     = 'finance_monthly_summaries';

// Methods
Future<void> saveAccounts(List<FinancialAccount>);
Future<List<FinancialAccount>> loadAccounts();

Future<void> saveTransactions(List<TransactionRecord>);
Future<List<TransactionRecord>> loadTransactions();

Future<void> saveFinanceCategories(List<FinanceCategory>);
Future<List<FinanceCategory>> loadFinanceCategories();

Future<void> saveBudgets(List<Budget>);
Future<List<Budget>> loadBudgets();

Future<void> saveBudgetedExpenses(List<BudgetedExpense>);
Future<List<BudgetedExpense>> loadBudgetedExpenses();

Future<void> saveBills(List<Bill>);
Future<List<Bill>> loadBills();

Future<void> saveReceivables(List<Receivable>);
Future<List<Receivable>> loadReceivables();

Future<void> saveMonthlySummaries(List<MonthlySummary>);
Future<List<MonthlySummary>> loadMonthlySummaries();
```

---

## No Seed Data

Accounts and categories are fully user-created. No defaults are seeded. The app shows an empty-state onboarding prompt until the user creates their first account and first category.

---

## Implementation Order

1. [ ] Create `lib/models/finance/` directory structure with all 8 models
2. [ ] Implement `fromJson` / `toJson` on every model (no logic, no calculations)
3. [ ] Add 8 storage keys + 16 CRUD methods to `StorageService`
4. [ ] Ensure `exportAllData()` and `importAllData()` in StorageService include finance keys

---

## RPG Impact

None in Phase 1 — purely data layer.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| `TransactionRecord` name collision with Dart/Flutter internals | Use `TransactionRecord` (not `Transaction`) |
| Account balance drift (balance ≠ sum of transactions) | Balance is the **source of truth** stored directly; transactions are the audit trail. Opening balance set on account creation. |
| Month string format inconsistency | Enforce `YYYY-MM` everywhere via a `DateUtils.toMonthKey(DateTime)` helper |
| Transfer creates two ledger entries | Transfer outbound from account A creates one `outflow` TransactionRecord on A and one `inflow` on B, linked by a shared `transferGroupId` |
| SharedPreferences size limits | Each list stored as a single JSON string. On large datasets (>500 transactions), migrate to SQLite. Flag in code with `// TODO: migrate to SQLite when txn count > 500` |

---

## Acceptance Criteria

- [ ] All 8 model classes have `fromJson` / `toJson` with no data loss roundtrip
- [ ] StorageService compiles and all new methods are callable
- [ ] `exportAllData()` includes all 8 finance keys
- [ ] No business logic or calculations in any Model class
- [ ] Sub-account round-trip: `parentAccountId` preserved correctly in JSON
- [ ] Transfer round-trip: both legs share `transferGroupId`, outflow on source + inflow on destination

---

*Present this plan for approval before writing any code. Proceed to Plan 004b after approval.*
