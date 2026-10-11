/// Pre-v2 entry point for settling a batch from the desktop Bills page.
///
/// The dialog itself is gone: [showWebBatchSettleDialog] is now a thin wrapper
/// over the unified Settle dialog in `web_settle_dialog.dart` (Plan 063 §5),
/// kept here under its old name and signature so the pre-v2 page and its
/// tests read unchanged. This file is removed with the rest of the pre-v2
/// web in Phase 11.
library;

export 'web_settle_dialog.dart' show showWebBatchSettleDialog;
