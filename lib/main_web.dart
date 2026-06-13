import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'views/web/treasury_web_app.dart';

/// Web entrypoint for the Treasury companion (Plan 042).
///
/// Deliberately minimal: only `.env` + `runApp`. NO NotificationService init
/// and NO home-widget callback — those plugins have no web implementation, and
/// the web shell ([TreasuryWebShell]) initializes Supabase auth + sync itself
/// after the first frame. `flutter build web -t lib/main_web.dart` only
/// compiles this entrypoint's transitive imports, so the mobile-only plugins
/// (health, home_widget, gemma, sqflite, etc.) never reach the web bundle.
void main() async {
  // Silence `debugPrint` in release: it is NOT stripped by the compiler (only
  // `assert` is), so the sync layer's userId / record-id / error-payload logs
  // would otherwise reach anyone with the browser console open. (Plan 052 S4)
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // NOTE: `.env` is bundled as a web asset (pubspec `flutter/assets`) and is
    // therefore downloadable by anyone as `assets/.env`. Only PUBLIC values may
    // live here (Supabase URL + anon key, Google web client id, redirect URL).
    // Never add a service-role key, AI key, or any secret. (Plan 052 S1)
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('main_web: failed to load .env: $e');
  }
  runApp(const TreasuryWebApp());
}
