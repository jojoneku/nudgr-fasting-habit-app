package com.nudgr.app

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.security.MessageDigest

/**
 * Notification listener behind the Capture Inbox (Plan 070).
 *
 * The system binds this once the user grants Notification access. It keeps
 * nothing from apps outside the allowlist except the app's label (so Settings
 * can offer it as a source), and for allowlisted apps it queues the title and
 * body text into [CaptureQueue] for Dart to parse. Notification text is never
 * logged.
 */
class TransactionNotificationListener : NotificationListenerService() {

    override fun onCreate() {
        super.onCreate()
        CaptureQueue.init(this)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        try {
            CaptureQueue.init(this)
            CaptureQueue.lastConnectedAt = System.currentTimeMillis()
        } catch (e: Throwable) {
            Log.w(TAG, "onListenerConnected failed: ${e.javaClass.simpleName}")
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        // A malformed notification must never take the listener down: once it
        // crashes the system may not rebind until the user toggles access.
        try {
            handle(sbn ?: return)
        } catch (e: Throwable) {
            Log.w(TAG, "capture skipped for ${sbn?.packageName}: ${e.javaClass.simpleName}")
        }
    }

    private fun handle(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        val now = System.currentTimeMillis()
        CaptureQueue.init(this)

        // Every posting app is remembered by label so the user can pick it as a
        // source later. Nothing else about it is stored.
        val label = appLabel(pkg)
        CaptureQueue.noteApp(pkg, label, now)

        if (pkg !in CaptureQueue.allowlist()) return

        val notification = sbn.notification ?: return
        val skipFlags = Notification.FLAG_GROUP_SUMMARY or Notification.FLAG_ONGOING_EVENT
        if (notification.flags and skipFlags != 0) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""

        // A sender-filtered source (Gmail) keeps only titles that name an
        // allowed sender; everything else is dropped here, unstored.
        val required = CaptureQueue.titleFilters(pkg)
        if (required.isNotEmpty() && required.none { title.contains(it, ignoreCase = true) }) return
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?.takeIf { it.isNotBlank() }
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: ""
        if (text.isBlank()) return

        // Two-minute bucket: the same text re-posted (progress updates, group
        // re-renders) collapses to one capture without hiding a genuine repeat
        // purchase minutes later.
        val fp = sha1Hex("$pkg|$text|${sbn.postTime / 120_000}")
        if (CaptureQueue.seen(fp)) return

        CaptureQueue.append(
            mapOf(
                "pkg" to pkg,
                "label" to label,
                "postTime" to sbn.postTime,
                "title" to title,
                "text" to text,
                "fp" to fp,
            ),
        )
        CaptureQueue.lastCaptureAt = now
        Log.d(TAG, "queued capture from $pkg")
    }

    private fun appLabel(pkg: String): String =
        try {
            @Suppress("DEPRECATION")
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString().ifBlank { pkg }
        } catch (e: Exception) {
            pkg
        }

    private fun sha1Hex(input: String): String =
        MessageDigest.getInstance("SHA-1")
            .digest(input.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private companion object {
        const val TAG = "TxnCapture"
    }
}
