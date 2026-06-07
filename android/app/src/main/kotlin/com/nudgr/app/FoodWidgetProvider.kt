package com.nudgr.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
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
            val views = RemoteViews(context.packageName, R.layout.widget_food)
            views.setOnClickPendingIntent(
                R.id.food_root,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("nudgr://food")
                )
            )

            val signedIn = widgetData.getBoolean("w_signed_in", false)
            if (!signedIn) {
                views.setViewVisibility(R.id.food_signin, View.VISIBLE)
                views.setTextViewText(R.id.food_calories, "—")
                views.setProgressBar(R.id.food_progress, 100, 0, false)
                views.setTextViewText(R.id.food_protein, "")
                appWidgetManager.updateAppWidget(id, views)
                continue
            }

            views.setViewVisibility(R.id.food_signin, View.GONE)
            val cals = widgetData.getLong("w_food_cals", 0L)
            val goal = widgetData.getLong("w_food_goal", 0L)
            val protein = widgetData.getLong("w_food_protein", 0L)
            val proteinGoal = widgetData.getLong("w_food_protein_goal", -1L)

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
}
