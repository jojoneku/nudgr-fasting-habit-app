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
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('main_web: failed to load .env: $e');
  }
  runApp(const TreasuryWebApp());
}
