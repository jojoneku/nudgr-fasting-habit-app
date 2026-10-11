/// Pre-v2 entry point for paying a credit card from the Dashboard and the
/// Bills page.
///
/// The dialog itself is gone: [showWebQuickPayDialog] is now a thin wrapper
/// over the unified Settle dialog in `web_settle_dialog.dart`
/// (`SettleKind.cardPayment`, Plan 063 §5), kept here under its old name and
/// signature so the pre-v2 pages read unchanged. This file is removed with
/// the rest of the pre-v2 web in Phase 11.
library;

export 'web_settle_dialog.dart' show showWebQuickPayDialog;
