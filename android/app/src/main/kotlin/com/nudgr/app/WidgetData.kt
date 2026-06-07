package com.nudgr.app

import android.content.SharedPreferences

/**
 * Widget-data accessors (Plan 039). Numeric snapshot values are transported as
 * Strings (the home_widget plugin can't safely round-trip Long/Int via the
 * method-channel codec — see WidgetSnapshot.toWidgetData). These parse them back.
 */
fun SharedPreferences.wLong(key: String, def: Long = 0L): Long =
    getString(key, null)?.toLongOrNull() ?: def

fun SharedPreferences.wInt(key: String, def: Int = 0): Int =
    getString(key, null)?.toIntOrNull() ?: def

fun SharedPreferences.wStr(key: String, def: String = ""): String =
    getString(key, def) ?: def

fun SharedPreferences.wBool(key: String, def: Boolean = false): Boolean =
    getBoolean(key, def)
