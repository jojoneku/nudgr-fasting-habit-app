import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'views/fasting_app.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await NotificationService().init();
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
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
              child: Text('Error during startup:\n$e', textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    ));
  }
}
