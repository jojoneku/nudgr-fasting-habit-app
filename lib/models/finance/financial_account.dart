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
  // Liability-only credit fields (creditCard / creditLine / bnpl). All nullable
  // so stored accounts from older versions deserialize unchanged.
  final double? creditLimit; // total approved limit
  final int? statementDay; // 1–28, day of month the statement closes
  final int? paymentDueDay; // 1–28, day of month payment is due
  final double? financeChargeRate; // monthly NOMINAL rate, e.g. 0.03 = 3%
  final String? creditBrand; // preset key, e.g. 'bpi_rewards'; null = manual
  final DateTime updatedAt;

  FinancialAccount({
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
    this.creditLimit,
    this.statementDay,
    this.paymentDueDay,
    this.financeChargeRate,
    this.creditBrand,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

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

  // --- Credit getters (meaningful only when isLiability) ---

  /// What you currently owe on this card/line. Zero for non-liability accounts.
  /// A negative balance means the card is overpaid (the bank owes you) — that's
  /// a credit balance, not extra debt, so it floors at zero here.
  double get currentPayable => isLiability && balance > 0 ? balance : 0;

  /// Limit minus what's owed. Null when no limit is set or not a liability.
  /// Uses [currentPayable] so an overpaid card can't show MORE than the limit
  /// as available (e.g. limit 50k, balance −2k must read 50k available, not 52k).
  double? get availableCredit => (isLiability && creditLimit != null)
      ? creditLimit! - currentPayable
      : null;

  /// Owed / limit as a 0..1 ratio for the utilization meter. Null when no limit.
  /// Floors at 0 via [currentPayable] so an overpaid card isn't negative.
  double? get utilization =>
      (isLiability && creditLimit != null && creditLimit! > 0)
          ? currentPayable / creditLimit!
          : null;

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
      creditLimit: (json['creditLimit'] as num?)?.toDouble(),
      statementDay: (json['statementDay'] as num?)?.toInt(),
      paymentDueDay: (json['paymentDueDay'] as num?)?.toInt(),
      financeChargeRate: (json['financeChargeRate'] as num?)?.toDouble(),
      creditBrand: json['creditBrand'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
        'creditLimit': creditLimit,
        'statementDay': statementDay,
        'paymentDueDay': paymentDueDay,
        'financeChargeRate': financeChargeRate,
        'creditBrand': creditBrand,
        'updatedAt': updatedAt.toIso8601String(),
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
    double? creditLimit,
    int? statementDay,
    int? paymentDueDay,
    double? financeChargeRate,
    String? creditBrand,
    DateTime? updatedAt,
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
      creditLimit: creditLimit ?? this.creditLimit,
      statementDay: statementDay ?? this.statementDay,
      paymentDueDay: paymentDueDay ?? this.paymentDueDay,
      financeChargeRate: financeChargeRate ?? this.financeChargeRate,
      creditBrand: creditBrand ?? this.creditBrand,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
