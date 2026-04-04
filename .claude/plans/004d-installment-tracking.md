# Plan 004d — Treasury Module: Installment Tracking
**Status:** DRAFT — Awaiting Approval
**Phase:** Extension to 004c
**Depends on:** Plan 004c completed (Bills & Receivables screen exists)

---

## Goal

Track installment purchases — credit card 0% plans, BNPL (SPayLater, BillEase), and any
purchase split into monthly payments. PH users commonly have 3/6/12/24-month installments
across multiple cards and wallets simultaneously.

An `Installment` is the *template* — it knows the total, the monthly slice, and the schedule.
Each month it surfaces as a payable in the Bills screen. Paying it creates a `TransactionRecord`
and advances the installment's progress.

---

## Model: `Installment`

```dart
class Installment {
  final String id;
  final String name;           // "MacBook Pro" / "Braces DP"
  final String accountId;      // the credit card / BNPL account being charged
  final double totalAmount;    // original purchase price
  final double monthlyAmount;  // amount per installment period
  final int totalMonths;       // total number of payments
  final String startMonth;     // 'YYYY-MM' — first payment month
  final String? note;
  final bool isActive;         // false = cancelled early

  // Derived (no storage needed)
  int paidCount(List<TransactionRecord> txns); // count txns with installmentId == id
  int get remainingMonths;
  double get remainingAmount;
  double get totalPaid; // monthlyAmount * paidCount
  bool isCompletedIn(List<TransactionRecord> txns); // paidCount >= totalMonths
  String monthForPaymentIndex(int i); // startMonth + i months
}
```

`TransactionRecord` gets one new nullable field: `String? installmentId`
— links the outflow transaction to its parent installment.

**Storage key:** `'installments'` → `List<Installment>` in `StorageService`

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/finance/installment.dart` | Create | Model |
| `lib/models/finance/transaction_record.dart` | Modify — add `installmentId` field | Model |
| `lib/services/storage_service.dart` | Modify — add `loadInstallments` / `saveInstallments` | Service |
| `lib/presenters/installment_presenter.dart` | Create | Presenter |
| `lib/views/treasury/bills/bills_receivables_view.dart` | Modify — add Installments section | View |
| `lib/views/treasury/bills/installment_list_tile.dart` | Create | View |
| `lib/views/treasury/bills/add_installment_sheet.dart` | Create | View |

---

## Presenter: `InstallmentPresenter`

```dart
class InstallmentPresenter extends ChangeNotifier {
  InstallmentPresenter(StorageService storage, LedgerPresenter ledger);

  bool get isLoading;
  String get selectedMonth;
  void setMonth(String month);

  // All active installments
  List<Installment> get installments;

  // Installments due this month (startMonth <= selectedMonth <= endMonth)
  List<Installment> get dueThisMonth;

  // Per-installment status for selectedMonth
  bool isPaidForMonth(String installmentId);       // has a txn with installmentId in selectedMonth
  int paidCount(String installmentId);             // how many months paid so far
  int remainingMonths(String installmentId);
  double remainingAmount(String installmentId);
  double get totalDueThisMonth;                    // sum of dueThisMonth monthly amounts
  double get totalPaidThisMonth;                   // sum of paid installments this month

  // CRUD
  Future<void> addInstallment(Installment i);
  Future<void> updateInstallment(Installment i);
  Future<void> deleteInstallment(String id);       // also deletes linked txns

  // Mark a month's payment paid → creates TransactionRecord with installmentId
  Future<void> markPaid(String installmentId, {double? overrideAmount, DateTime? date});
  Future<void> markUnpaid(String installmentId);   // deletes linked txn for selectedMonth
}
```

---

## View: Bills Screen — Installments Section

Added as a new collapsible section (`ExpansionTile`) inside `BillsReceivablesView`,
after Bills and Receivables.

### `InstallmentListTile` layout (per installment in `dueThisMonth`):

```
┌──────────────────────────────────────────────────────────┐
│  [●] GCash Credit — iPhone 15            ₱5,000 / month  │
│      Progress: ████████░░  8 / 12 months  ₱20,000 left   │
│      [Mark Paid]                        [paid — May 2026] │
└──────────────────────────────────────────────────────────┘
```

- Left dot: account accent color
- Progress bar: `paidCount / totalMonths` — LinearProgressIndicator
- If paid this month: row shows green check + paid date; swipe to undo
- "Mark Paid" → confirm sheet (shows amount, date, account; amount is pre-filled but editable)

### Section header stat bar:
```
Installments: ₱15,000 due  |  ₱5,000 paid  |  4 remaining
```

### Add Installment Sheet fields:
- Name (required)
- Account (dropdown — credit cards and BNPL accounts only)
- Total Amount
- Monthly Amount (auto-computed from total ÷ months, editable)
- Number of Months (stepper: 3 / 6 / 12 / 24 / custom)
- Start Month (month picker — defaults to current month)
- Note (optional)

---

## Transaction Integration

When `markPaid` is called:
1. Creates `TransactionRecord`:
   - `type: outflow`
   - `accountId`: installment's accountId
   - `categoryId`: a system category `'installment'` (auto-created if missing)
   - `amount`: monthlyAmount (or overrideAmount)
   - `description`: `"${installment.name} — Installment ${paidCount + 1}/${totalMonths}"`
   - `installmentId`: installment.id
2. Calls `LedgerPresenter.addTransaction(txn)`
3. Notifies listeners

When `markUnpaid`:
1. Finds the outflow txn in `selectedMonth` where `installmentId == id`
2. Calls `LedgerPresenter.deleteTransaction(txn.id)`

---

## RPG Impact

| Event | Reward |
|---|---|
| Final installment payment (last month paid) | +50 XP — "Debt cleared!" |
| All installments due this month paid | +20 XP |
| No active installments for a full month | +30 XP — "Debt-free month" badge |

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| `startMonth` in past, user catches up multiple months | "Mark Paid" applies to `selectedMonth` — user navigates to each past month to catch up |
| Monthly amount doesn't divide evenly into total | Allow override amount on final payment; warn if sum of payments will differ from totalAmount |
| Installment account is deleted | Show warning on the installment tile; keep installment as orphaned but inactive |
| 0% vs interest-bearing | No interest calculation in v1; add `interestRate` field and amortization in a future version |
| Recurring bill + installment overlap | Installments are a separate section; no deduplication needed |

---

## Acceptance Criteria

- [ ] Installment list shows only installments due in `selectedMonth`
- [ ] `markPaid` creates a linked `TransactionRecord` with correct `installmentId`
- [ ] Progress bar reflects total paid months across all time, not just current month
- [ ] Last payment marks installment as complete; tile greys out in future months
- [ ] Deleting an installment prompts confirmation and removes linked transactions
- [ ] `dueThisMonth` total shown in Bills screen header
- [ ] No logic in any `build()` method
- [ ] Touch targets ≥ 44×44px

---

*Extends Plan 004c. Can be implemented independently as a new section in the existing Bills view.*
