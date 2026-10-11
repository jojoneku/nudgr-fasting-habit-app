/// Build-time switches for the Treasury web companion.
library;

/// Treasury web v2 (Plan 063): the redesigned shell and pages.
///
/// Off by default. While it is off `_TreasuryWebHome` builds the pre-v2
/// `WebShell` and pages, so every v2 phase can merge to `dev` (which
/// auto-promotes to `main` and deploys) with the live site unchanged. CI's
/// `deploy_web` passes `--dart-define=WEB_V2=true` in Phase 11; the old shell
/// and pages stay in the tree until then and are deleted once the flip has
/// shipped and settled.
///
/// Local run: `flutter run -t lib/main_web.dart --dart-define=WEB_V2=true`.
const bool kWebV2 = bool.fromEnvironment('WEB_V2');
