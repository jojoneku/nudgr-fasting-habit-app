package com.nudgr.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Food glance widget (Plan 039). Taps deep-link to the nutrition screen. */
class FoodWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            // A throwing render would leave the widget silently stuck on its
            // last state until the next push — log and keep the others alive.
            try {
                render(context, appWidgetManager, id, widgetData)
            } catch (e: Exception) {
                Log.e("FoodWidget", "render failed", e)
            }
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        id: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_food)
        views.setOnClickPendingIntent(
            R.id.food_root,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("nudgr://food")
            )
        )

        val signedIn = widgetData.wBool("w_signed_in")
        if (!signedIn) {
            views.setViewVisibility(R.id.food_signin, View.VISIBLE)
            views.setTextViewText(R.id.food_calories, "—")
            views.setProgressBar(R.id.food_progress, 100, 0, false)
            views.setTextViewText(R.id.food_protein, "")
            appWidgetManager.updateAppWidget(id, views)
            return
        }

        views.setViewVisibility(R.id.food_signin, View.GONE)
        // Past midnight a new day starts at 0 logged — don't show yesterday's
        // totals when the snapshot predates today (app not opened since).
        val fresh = widgetData.wIsToday()
        val cals = if (fresh) widgetData.wLong("w_food_cals") else 0L
        val protein = if (fresh) widgetData.wLong("w_food_protein") else 0L
        val goal = widgetData.wLong("w_food_goal")
        val proteinGoal = widgetData.wLong("w_food_protein_goal", -1L)

        views.setTextViewText(
            R.id.food_calories,
            if (goal > 0) "$cals / $goal kcal" else "$cals kcal"
        )
        val pct = if (goal > 0) ((cals * 100) / goal).coerceIn(0L, 100L).toInt() else 0
        views.setProgressBar(R.id.food_progress, 100, pct, false)
        views.setTextViewText(
            R.id.food_protein,
            if (proteinGoal >= 0) "Protein $protein / $proteinGoal g" else "Protein $protein g"
        )
        appWidgetManager.updateAppWidget(id, views)
    }
}
