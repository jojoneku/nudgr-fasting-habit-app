// Credit-card brand presets. These are *opt-in seeds* the user can pick on the
// account setup screen — picking one fills in default rate/fee figures, which
// the user can then edit. No institution data is ever forced onto an account.
//
// Figures are sourced from the issuer's public rates pages and the BSP cap
// (Circular 1165: max 3%/month = 36%/year on the unpaid balance, reviewed every
// 6 months). They are defaults, not guarantees — always verify against your
// statement. See docs/credit_accounts_spec.md for sources.

class CreditBrandPreset {
  final String
      key; // stable id stored on the account (FinancialAccount.creditBrand)
  final String label; // shown in the picker
  final double monthlyFinanceRate; // nominal monthly rate, e.g. 0.03 = 3%
  final double minPaymentRate; // fraction of balance, e.g. 0.0357 = 3.57%
  final double minPaymentFloor; // minimum due never below this (PHP)
  final double lateFeeFlat; // late fee = min(lateFeeFlat, unpaid min due)

  const CreditBrandPreset({
    required this.key,
    required this.label,
    required this.monthlyFinanceRate,
    required this.minPaymentRate,
    required this.minPaymentFloor,
    required this.lateFeeFlat,
  });
}

/// BPI Rewards (Mastercard/Visa) — regular-purchase finance charge 3% nominal
/// monthly (2.73% effective), min due 3.57% of balance or ₱850 (whichever is
/// higher), late fee ₱850 or the unpaid min due (whichever is lower).
const kBpiRewards = CreditBrandPreset(
  key: 'bpi_rewards',
  label: 'BPI Rewards (Mastercard/Visa)',
  monthlyFinanceRate: 0.03,
  minPaymentRate: 0.0357,
  minPaymentFloor: 850,
  lateFeeFlat: 850,
);

/// BPI Free+ — lower 2.5% nominal monthly finance charge; same min-due/late-fee
/// structure as other BPI cards.
const kBpiFreePlus = CreditBrandPreset(
  key: 'bpi_free_plus',
  label: 'BPI Free+',
  monthlyFinanceRate: 0.025,
  minPaymentRate: 0.0357,
  minPaymentFloor: 850,
  lateFeeFlat: 850,
);

/// All presets available in the picker. Add new brands here as they're verified.
const List<CreditBrandPreset> kCreditBrandPresets = [
  kBpiRewards,
  kBpiFreePlus,
];

/// Looks up a preset by its stored [key], or null if unknown/manual.
CreditBrandPreset? creditBrandPresetByKey(String? key) {
  if (key == null) return null;
  for (final p in kCreditBrandPresets) {
    if (p.key == key) return p;
  }
  return null;
}
