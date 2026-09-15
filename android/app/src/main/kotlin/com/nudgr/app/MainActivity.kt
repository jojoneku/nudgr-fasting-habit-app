package com.nudgr.app

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    private val channel = "com.nudgr.app/health_connect"
    private val systemSettingsChannel = "com.nudgr.app/system_settings"
    private val lockScreenChannel = "com.nudgr.app/lockscreen"

    /** True while this launch is allowed to draw over the keyguard. */
    private var showingOverLockScreen = false

    // Intent extra key flutter_local_notifications puts the payload under.
    private val notificationPayloadExtra = "payload"

    // Mirrors AlarmNotification.payloadFlag on the Dart side.
    private val alarmPayloadFlag = "alarm"

    // Present when the launch came from a notification ACTION BUTTON rather
    // than the alarm itself.
    private val notificationActionExtra = "actionId"

    override fun onCreate(savedInstanceState: Bundle?) {
        // Applied before super.onCreate so the window carries the flags the
        // first time it is shown — setting them after the activity is already
        // visible makes the lock screen flash before the alarm appears.
        applyLockScreenFlagsFor(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // launchMode is singleTop, so an alarm arriving while the app is warm
        // comes through here rather than onCreate.
        applyLockScreenFlagsFor(intent)
    }

    /**
     * Grants this launch permission to wake the screen and draw over the
     * keyguard, but only when it was started by an alarm-style notification.
     * A normal launch (or a tap on an ordinary reminder) stays behind the lock
     * screen, which is what keeps the Hub off a locked phone.
     */
    private fun applyLockScreenFlagsFor(intent: Intent?) {
        if (!isAlarmLaunch(intent)) return
        setLockScreenFlags(true)
    }

    private fun isAlarmLaunch(intent: Intent?): Boolean {
        val extras = intent?.extras ?: return false
        // An action-button tap ("Mark as Done" shows UI, so it launches the
        // activity) carries the same alarm payload as the alarm itself. Treat
        // it as an ordinary launch: the user is acting from the shade, and
        // granting it the keyguard would put the Hub on a locked screen —
        // precisely what scoping these flags is meant to prevent. Dart's
        // handler makes the same distinction on actionId.
        if (extras.getString(notificationActionExtra) != null) return false
        // Fast path: the key flutter_local_notifications uses today. The
        // fallback scan keeps this working if the plugin ever renames it —
        // the extras bundle is a handful of entries, and Dart re-asserts the
        // flags via `acquire` regardless, so a miss only costs a brief flash.
        val payload = extras.getString(notificationPayloadExtra)
        if (payload != null) return carriesAlarmFlag(payload)
        return extras.keySet().any { key ->
            carriesAlarmFlag(extras.getString(key))
        }
    }

    private fun carriesAlarmFlag(payload: String?): Boolean {
        if (payload.isNullOrEmpty()) return false
        return try {
            JSONObject(payload).optBoolean(alarmPayloadFlag, false)
        } catch (e: Exception) {
            false // not JSON (e.g. the OTA install path)
        }
    }

    private fun setLockScreenFlags(enabled: Boolean) {
        showingOverLockScreen = enabled
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
        } else {
            // API 26: the setters do not exist yet, so use the window flags
            // they replaced.
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            @Suppress("DEPRECATION")
            if (enabled) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets the alarm screen hand the keyguard back once it is dismissed,
        // so the app behind it is not left visible on a locked device.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, lockScreenChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        setLockScreenFlags(true)
                        result.success(null)
                    }
                    "release" -> {
                        setLockScreenFlags(false)
                        result.success(null)
                    }
                    "isShowingOverLockScreen" -> result.success(showingOverLockScreen)
                    else -> result.notImplemented()
                }
            }
        // App-level system settings deep links (e.g. when notifications are
        // blocked and the runtime prompt can no longer be shown).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Android 14+ (API 34) stopped auto-granting
                    // USE_FULL_SCREEN_INTENT to apps that are not calling or
                    // alarm-clock apps. Without it an alarm-style quest
                    // silently degrades to an ordinary heads-up banner, so the
                    // quest editor checks this before promising otherwise.
                    "canUseFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT < 34) {
                            result.success(true)
                        } else {
                            val nm = getSystemService(NotificationManager::class.java)
                            result.success(nm?.canUseFullScreenIntent() ?: false)
                        }
                    }
                    "openFullScreenIntentSettings" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                Uri.parse("package:$packageName"),
                            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "openNotificationSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getOnDeviceStepsSpn" -> {
                        // Canonical resolution of the device's on-device steps
                        // Synthetic Package Name via HealthConnectManager
                        // .getCurrentDeviceDataSource() (Android 14, SDK
                        // extension 20+). Reflection avoids a compileSdk
                        // dependency on the extension symbols; any failure
                        // returns null so Dart falls back to the SPN prefix.
                        try {
                            if (Build.VERSION.SDK_INT < 34) {
                                result.success(null)
                            } else {
                                val mgrClass = Class.forName(
                                    "android.health.connect.HealthConnectManager")
                                val mgr = getSystemService(mgrClass)
                                if (mgr == null) {
                                    result.success(null)
                                } else {
                                    val dataSource = mgrClass
                                        .getMethod("getCurrentDeviceDataSource")
                                        .invoke(mgr)
                                    val origin = dataSource?.javaClass
                                        ?.getMethod("getDeviceDataOrigin")
                                        ?.invoke(dataSource)
                                    val pkg = origin?.javaClass
                                        ?.getMethod("getPackageName")
                                        ?.invoke(origin) as? String
                                    result.success(pkg)
                                }
                            }
                        } catch (e: Throwable) {
                            result.success(null)
                        }
                    }
                    "openPermissionsSettings" -> {
                        try {
                            // Opens Health Connect permissions screen for our app directly
                            val intent = Intent("android.health.connect.action.MANAGE_HEALTH_PERMISSIONS").apply {
                                putExtra(Intent.EXTRA_PACKAGE_NAME, packageName)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            // Fallback: open Health Connect main app
                            try {
                                val fallback = packageManager
                                    .getLaunchIntentForPackage("com.google.android.apps.healthdata")
                                if (fallback != null) {
                                    startActivity(fallback)
                                    result.success(null)
                                } else {
                                    result.error("NOT_FOUND", "Health Connect not installed", null)
                                }
                            } catch (e2: Exception) {
                                result.error("ERROR", e2.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
