package com.nudgr.app

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channel = "com.nudgr.app/health_connect"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
