import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'services/notification_service.dart';
import 'services/widget_bridge_service.dart';
import 'views/fasting_app.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    await dotenv.load(fileName: '.env');

    try {
      await NotificationService().init();
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }

    // Home-screen widget inline actions run this callback in a background
    // isolate; it only records the tap and is drained safely on next foreground.
    try {
      await HomeWidget.registerInteractivityCallback(
          WidgetBridgeService.onInteractiveAction);
    } catch (e) {
      debugPrint('Error registering widget interactivity callback: $e');
    }

    runApp(const FastingApp());
  } catch (e, stack) {
    debugPrint('Error in main: $e');
    debugPrint(stack.toString());
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error during startup:\n$e',
                  textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    ));
  }
}
