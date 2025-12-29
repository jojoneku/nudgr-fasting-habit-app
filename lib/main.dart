import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'views/fasting_app.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // Handle background notification tap if needed
}

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      tz.initializeTimeZones();
    } catch (e) {
      debugPrint('Error initializing timezones: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    try {
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {},
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
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
