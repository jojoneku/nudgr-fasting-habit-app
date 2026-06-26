package com.nudgr.app

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channel = "com.nudgr.app/health_connect"
    private val systemSettingsChannel = "com.nudgr.app/system_settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // App-level system settings deep links (e.g. when notifications are
        // blocked and the runtime prompt can no longer be shown).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
