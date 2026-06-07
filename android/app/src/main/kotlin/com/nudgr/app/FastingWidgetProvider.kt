package com.nudgr.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Fasting flagship home-screen widget (Plan 039).
 *
 * Renders the denormalized snapshot the app pushes via home_widget. The
 * Chronometer ticks natively, so elapsed time stays live even when the Flutter
 * process is dead. Start/End fire inline background actions (queued + applied on
 * next app foreground); the card body deep-links to the timer screen.
 */
class FastingWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_fasting)

            val signedIn = widgetData.getBoolean("w_signed_in", false)
            val isFasting = widgetData.getBoolean("w_is_fasting", false)

            // Card tap → open the fasting screen.
            views.setOnClickPendingIntent(
                R.id.fasting_root,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("nudgr://fasting")
                )
            )
            // Inline actions → background callback (no app launch).
            views.setOnClickPendingIntent(
                R.id.btn_start,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("nudgr://startfast"))
            )
            views.setOnClickPendingIntent(
                R.id.btn_end,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("nudgr://stopfast"))
            )

            if (!signedIn) {
                views.setViewVisibility(R.id.fasting_signin, View.VISIBLE)
                views.setViewVisibility(R.id.fasting_time, View.GONE)
                views.setViewVisibility(R.id.fasting_idle, View.GONE)
                views.setViewVisibility(R.id.fasting_progress, View.GONE)
                views.setViewVisibility(R.id.btn_start, View.GONE)
                views.setViewVisibility(R.id.btn_end, View.GONE)
                views.setTextViewText(R.id.fasting_phase, "")
                views.setTextViewText(R.id.fasting_streak, "")
                appWidgetManager.updateAppWidget(id, views)
                continue
            }

            views.setViewVisibility(R.id.fasting_signin, View.GONE)
            val streak = widgetData.getLong("w_fast_streak", 0L)

            if (isFasting) {
                val startMillis = widgetData.getLong("w_fast_start_millis", 0L)
                val goalHours = widgetData.getLong("w_fast_goal_hours", 16L)
                val phase = widgetData.getString("w_fast_phase", "") ?: ""

                // Chronometer counts up from the fast start, ticking on its own.
                val base = SystemClock.elapsedRealtime() -
                    (System.currentTimeMillis() - startMillis)
                views.setChronometer(R.id.fasting_time, base, null, true)

                val elapsedMs = System.currentTimeMillis() - startMillis
                val targetMs = goalHours * 3600_000L
                val pct = if (targetMs > 0) {
                    ((elapsedMs * 100) / targetMs).coerceIn(0L, 100L).toInt()
                } else 0
                views.setProgressBar(R.id.fasting_progress, 100, pct, false)

                views.setViewVisibility(R.id.fasting_time, View.VISIBLE)
                views.setViewVisibility(R.id.fasting_idle, View.GONE)
                views.setViewVisibility(R.id.fasting_progress, View.VISIBLE)
                views.setViewVisibility(R.id.btn_start, View.GONE)
                views.setViewVisibility(R.id.btn_end, View.VISIBLE)
                views.setTextViewText(R.id.fasting_phase, phase)
                views.setTextViewText(R.id.fasting_streak, "Goal ${goalHours}h")
            } else {
                views.setViewVisibility(R.id.fasting_time, View.GONE)
                views.setViewVisibility(R.id.fasting_idle, View.VISIBLE)
                views.setViewVisibility(R.id.fasting_progress, View.GONE)
                views.setViewVisibility(R.id.btn_start, View.VISIBLE)
                views.setViewVisibility(R.id.btn_end, View.GONE)
                views.setTextViewText(R.id.fasting_phase, "")
                val streakLabel = if (streak > 0) "🔥 $streak day streak" else "Tap to begin"
                views.setTextViewText(R.id.fasting_streak, streakLabel)
            }

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
