package com.nudgr.app

import android.content.SharedPreferences

/**
 * Widget-data accessors (Plan 039). Numeric snapshot values are transported as
 * Strings (the home_widget plugin can't safely round-trip Long/Int via the
 * method-channel codec — see WidgetSnapshot.toWidgetData). These parse them back.
 *
 * Reads go through `all[key]` instead of the typed getters: installs that ran the
 * pre-51564da build still hold Int-typed entries on disk, and `getString()` on an
 * Int-typed entry throws ClassCastException — crashing the provider (and the app
 * process it runs in) on every render until the entry is overwritten. Tolerating
 * any stored type makes the upgrade path safe; the next snapshot push rewrites
 * every key in the new format.
 */
fun SharedPreferences.wLong(key: String, def: Long = 0L): Long =
    when (val v = all[key]) {
        is Long -> v
        is Int -> v.toLong()
        is String -> v.toLongOrNull() ?: def
        else -> def
    }

fun SharedPreferences.wInt(key: String, def: Int = 0): Int =
    when (val v = all[key]) {
        is Int -> v
        is Long -> v.toInt()
        is String -> v.toIntOrNull() ?: def
        else -> def
    }

fun SharedPreferences.wStr(key: String, def: String = ""): String =
    when (val v = all[key]) {
        is String -> v
        null -> def
        else -> v.toString()
    }

fun SharedPreferences.wBool(key: String, def: Boolean = false): Boolean =
    when (val v = all[key]) {
        is Boolean -> v
        is String -> v.equals("true", ignoreCase = true)
        else -> def
    }
