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
//   6. Custodian                → money handed to you but not yours (friend's cash, group
//                                  fund, collected payments). Excluded from net worth.
//
// Top-level (parentAccountId == null):
//   bank, ewallet, cash, creditCard, creditLine, bnpl, investment, custodian
// Sub-account (parentAccountId != null):
//   savings, goal, timeDeposit, investment (can also be a top-level product)
//
// Liability types (balance = what you owe, not what you have):
//   creditCard, creditLine, bnpl
enum AccountCategory {
  // Liquid / asset accounts
  bank,
  ewallet,
  cash,
  // Locked / sub-accounts (ring-fenced pockets)
  savings,
  goal,
  timeDeposit,
  // Liability accounts — balance represents debt owed
  creditCard,
  creditLine,
  bnpl,
  // Non-liquid asset accounts
  investment,
  // External — money held on behalf of others, not part of personal net worth
  custodian,
}

// Supports both main accounts and sub-accounts (savings pots, goals, time deposits).
//
// Main account:  parentAccountId == null, category ∈ {bank, ewallet, cash, ...}
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
  final String? parentAccountId; // null = top-level account
  final double balance; // current balance (user-maintained)
  final String currency; // default 'PHP'
  final String colorHex;
  final String icon; // MDI icon name
  final bool isActive;
  final double? goalTarget; // only used when category == goal
  final DateTime? maturityDate; // only used when category == timeDeposit
  final String?
      linkedAccountId; // custodian only: the liquid account where these funds physically live

  const FinancialAccount({
    required this.id,
    required this.name,
    required this.category,
    this.parentAccountId,
    required this.balance,
    this.currency = 'PHP',
    required this.colorHex,
    required this.icon,
    this.isActive = true,
    this.goalTarget,
    this.maturityDate,
    this.linkedAccountId,
  });

  bool get isSubAccount => parentAccountId != null;
  bool get isLiquid =>
      category == AccountCategory.bank ||
      category == AccountCategory.ewallet ||
      category == AccountCategory.cash;
  bool get isLocked =>
      category == AccountCategory.savings ||
      category == AccountCategory.goal ||
      category == AccountCategory.timeDeposit ||
      category == AccountCategory.investment;
  // balance = debt owed, not funds available
  bool get isLiability =>
      category == AccountCategory.creditCard ||
      category == AccountCategory.creditLine ||
      category == AccountCategory.bnpl;
  // balance = funds held for others — excluded from net worth and liquid cash
  bool get isCustodian => category == AccountCategory.custodian;

  factory FinancialAccount.fromJson(Map<String, dynamic> json) {
    return FinancialAccount(
      id: json['id'] as String,
      name: json['name'] as String,
      category: AccountCategory.values.byName(json['category'] as String),
      parentAccountId: json['parentAccountId'] as String?,
      balance: (json['balance'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'PHP',
      colorHex: json['colorHex'] as String,
      icon: json['icon'] as String,
      isActive: json['isActive'] as bool? ?? true,
      goalTarget: (json['goalTarget'] as num?)?.toDouble(),
      maturityDate: json['maturityDate'] != null
          ? DateTime.parse(json['maturityDate'] as String)
          : null,
      linkedAccountId: json['linkedAccountId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'parentAccountId': parentAccountId,
        'balance': balance,
        'currency': currency,
        'colorHex': colorHex,
        'icon': icon,
        'isActive': isActive,
        'goalTarget': goalTarget,
        'maturityDate': maturityDate?.toIso8601String(),
        'linkedAccountId': linkedAccountId,
      };

  FinancialAccount copyWith({
    String? name,
    AccountCategory? category,
    String? parentAccountId,
    double? balance,
    String? currency,
    String? colorHex,
    String? icon,
    bool? isActive,
    double? goalTarget,
    DateTime? maturityDate,
    String? linkedAccountId,
  }) {
    return FinancialAccount(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      parentAccountId: parentAccountId ?? this.parentAccountId,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      colorHex: colorHex ?? this.colorHex,
      icon: icon ?? this.icon,
      isActive: isActive ?? this.isActive,
      goalTarget: goalTarget ?? this.goalTarget,
      maturityDate: maturityDate ?? this.maturityDate,
      linkedAccountId: linkedAccountId ?? this.linkedAccountId,
    );
  }
}
