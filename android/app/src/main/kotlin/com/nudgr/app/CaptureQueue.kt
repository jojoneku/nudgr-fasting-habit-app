package com.nudgr.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistent state for transaction capture (Plan 070).
 *
 * Owns everything the notification listener and the `com.nudgr.app/capture`
 * channel share: the raw-capture queue, the package allowlist, the duplicate
 * fingerprint ring, the "recent apps" picker data and two timestamps. All of
 * it lives in its own SharedPreferences file (`capture_queue`) — never in the
 * home_widget or Flutter prefs — and is device-scoped: Dart drains the queue
 * into whichever user is signed in.
 *
 * The listener writes from a binder thread while the channel reads on main, so
 * every member synchronizes on this object. In-process SharedPreferences share
 * one memory cache, so `apply()` keeps both sides consistent without blocking.
 */
object CaptureQueue {
    private const val PREFS = "capture_queue"
    private const val KEY_QUEUE = "queue"
    private const val KEY_ALLOWLIST = "allowlist"
    private const val KEY_TITLE_FILTERS = "titleFilters"
    private const val KEY_FINGERPRINTS = "recentFingerprints"
    private const val KEY_RECENT_APPS = "recentApps"
    private const val KEY_LAST_CONNECTED = "lastConnectedAt"
    private const val KEY_LAST_CAPTURE = "lastCaptureAt"

    const val MAX_QUEUE = 500
    const val MAX_FINGERPRINTS = 200
    const val MAX_RECENT_APPS = 50
    const val RECENT_APP_WINDOW_MS = 7L * 24 * 60 * 60 * 1000

    /** String fields of one raw capture, as it crosses the channel (RawCapture.toMap). */
    private val STRING_FIELDS = listOf("pkg", "label", "title", "text", "fp")

    @Volatile
    private var prefs: SharedPreferences? = null

    /** Idempotent; call with any Context before using the other members. */
    fun init(context: Context) {
        if (prefs != null) return
        synchronized(this) {
            if (prefs == null) {
                prefs = context.applicationContext
                    .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            }
        }
    }

    private fun prefs(): SharedPreferences =
        prefs ?: error("CaptureQueue.init(context) must run before use")

    // ── Queue ────────────────────────────────────────────────────────────

    /** Appends one capture; past [MAX_QUEUE] the oldest entries are dropped. */
    @Synchronized
    fun append(raw: Map<String, Any?>) {
        val arr = readArray(KEY_QUEUE)
        arr.put(toEntry(raw))
        writeArray(KEY_QUEUE, trimFront(arr, MAX_QUEUE))
    }

    /** Returns every queued capture and clears the queue in one step. */
    @Synchronized
    fun drain(): List<Map<String, Any?>> {
        val arr = readArray(KEY_QUEUE)
        val out = ArrayList<Map<String, Any?>>(arr.length())
        for (i in 0 until arr.length()) {
            arr.optJSONObject(i)?.let { out.add(fromEntry(it)) }
        }
        prefs().edit().remove(KEY_QUEUE).apply()
        return out
    }

    /**
     * Puts drained captures back at the front (they predate anything queued
     * since). The cap still drops oldest first, so a full queue sheds the
     * requeued entries before the fresh ones.
     */
    @Synchronized
    fun requeue(captures: List<Map<*, *>>) {
        if (captures.isEmpty()) return
        val merged = JSONArray()
        captures.forEach { merged.put(toEntry(it)) }
        val existing = readArray(KEY_QUEUE)
        for (i in 0 until existing.length()) merged.put(existing.opt(i))
        writeArray(KEY_QUEUE, trimFront(merged, MAX_QUEUE))
    }

    // ── Allowlist ────────────────────────────────────────────────────────

    /**
     * [titleFilters]: per package, words the notification title must contain
     * (case-insensitive) for the listener to keep it. Gmail's title is the
     * sender, so {"com.google.android.gm": ["BPI"]} keeps bank mail only.
     * A package with no entry is kept whatever its title says.
     */
    @Synchronized
    fun setAllowlist(packages: Set<String>, titleFilters: Map<String, List<String>> = emptyMap()) {
        val filters = JSONObject()
        for ((pkg, words) in titleFilters) {
            val clean = words.map { it.trim() }.filter { it.isNotEmpty() }
            if (pkg in packages && clean.isNotEmpty()) filters.put(pkg, JSONArray(clean))
        }
        prefs().edit()
            .putStringSet(KEY_ALLOWLIST, HashSet(packages))
            .putString(KEY_TITLE_FILTERS, filters.toString())
            .apply()
    }

    @Synchronized
    fun allowlist(): Set<String> =
        prefs().getStringSet(KEY_ALLOWLIST, null)?.let { HashSet(it) } ?: emptySet()

    /** Title words required for [pkg]; empty means no title filter. */
    @Synchronized
    fun titleFilters(pkg: String): List<String> {
        val arr = readObject(KEY_TITLE_FILTERS).optJSONArray(pkg) ?: return emptyList()
        return (0 until arr.length()).mapNotNull { arr.optString(it).takeIf { s -> s.isNotBlank() } }
    }

    // ── Duplicate fingerprints ───────────────────────────────────────────

    /** True if [fp] was seen recently; otherwise records it and returns false. */
    @Synchronized
    fun seen(fp: String): Boolean {
        val ring = readArray(KEY_FINGERPRINTS)
        for (i in 0 until ring.length()) {
            if (ring.optString(i) == fp) return true
        }
        ring.put(fp)
        writeArray(KEY_FINGERPRINTS, trimFront(ring, MAX_FINGERPRINTS))
        return false
    }

    // ── Recent apps (labels only — never notification text) ──────────────

    @Synchronized
    fun noteApp(pkg: String, label: String, now: Long) {
        val apps = pruneApps(readObject(KEY_RECENT_APPS), now)
        apps.put(pkg, JSONObject().put("label", label).put("lastSeen", now))
        while (apps.length() > MAX_RECENT_APPS) {
            var oldestKey: String? = null
            var oldestSeen = Long.MAX_VALUE
            for (key in apps.keys()) {
                val seen = apps.optJSONObject(key)?.optLong("lastSeen") ?: 0L
                if (seen < oldestSeen) {
                    oldestSeen = seen
                    oldestKey = key
                }
            }
            apps.remove(oldestKey ?: break)
        }
        prefs().edit().putString(KEY_RECENT_APPS, apps.toString()).apply()
    }

    /** Apps seen in the last 7 days, most recent first. */
    @Synchronized
    fun recentApps(now: Long): List<Map<String, Any?>> {
        val apps = pruneApps(readObject(KEY_RECENT_APPS), now)
        val out = ArrayList<Map<String, Any?>>(apps.length())
        for (key in apps.keys()) {
            val entry = apps.optJSONObject(key) ?: continue
            out.add(
                mapOf(
                    "pkg" to key,
                    "label" to entry.optString("label", key),
                    "lastSeen" to entry.optLong("lastSeen"),
                ),
            )
        }
        out.sortByDescending { it["lastSeen"] as Long }
        return out
    }

    private fun pruneApps(apps: JSONObject, now: Long): JSONObject {
        val cutoff = now - RECENT_APP_WINDOW_MS
        val stale = ArrayList<String>()
        for (key in apps.keys()) {
            val seen = apps.optJSONObject(key)?.optLong("lastSeen") ?: 0L
            if (seen < cutoff) stale.add(key)
        }
        stale.forEach { apps.remove(it) }
        return apps
    }

    // ── Timestamps ───────────────────────────────────────────────────────

    /** When the listener last connected; 0 if never. */
    var lastConnectedAt: Long
        @Synchronized get() = prefs().getLong(KEY_LAST_CONNECTED, 0L)
        @Synchronized set(value) {
            prefs().edit().putLong(KEY_LAST_CONNECTED, value).apply()
        }

    /** When a capture was last queued; 0 if never. */
    var lastCaptureAt: Long
        @Synchronized get() = prefs().getLong(KEY_LAST_CAPTURE, 0L)
        @Synchronized set(value) {
            prefs().edit().putLong(KEY_LAST_CAPTURE, value).apply()
        }

    // ── JSON helpers ─────────────────────────────────────────────────────

    private fun readArray(key: String): JSONArray =
        try {
            JSONArray(prefs().getString(key, null) ?: "[]")
        } catch (e: Exception) {
            JSONArray() // corrupt entry: start over rather than wedge the queue
        }

    private fun readObject(key: String): JSONObject =
        try {
            JSONObject(prefs().getString(key, null) ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }

    private fun writeArray(key: String, arr: JSONArray) {
        prefs().edit().putString(key, arr.toString()).apply()
    }

    /** Keeps the last [max] entries (JSONArray has no efficient front removal). */
    private fun trimFront(arr: JSONArray, max: Int): JSONArray {
        if (arr.length() <= max) return arr
        val trimmed = JSONArray()
        for (i in arr.length() - max until arr.length()) trimmed.put(arr.opt(i))
        return trimmed
    }

    private fun toEntry(raw: Map<*, *>): JSONObject {
        val obj = JSONObject()
        for (field in STRING_FIELDS) obj.put(field, raw[field]?.toString() ?: "")
        obj.put("postTime", (raw["postTime"] as? Number)?.toLong() ?: 0L)
        return obj
    }

    private fun fromEntry(obj: JSONObject): Map<String, Any?> {
        val map = HashMap<String, Any?>(STRING_FIELDS.size + 1)
        for (field in STRING_FIELDS) map[field] = obj.optString(field, "")
        map["postTime"] = obj.optLong("postTime", 0L)
        return map
    }
}
