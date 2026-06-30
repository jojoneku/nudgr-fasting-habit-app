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

/**
 * Weight glance widget. Renders the latest logged weight + delta from the
 * denormalized snapshot the app pushes via home_widget; the card deep-links to
 * the weight log.
 */
class WeightWidgetProvider : HomeWidgetProvider() {
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
                Log.e("WeightWidget", "render failed", e)
            }
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        id: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_weight)

        views.setOnClickPendingIntent(
            R.id.weight_root,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("nudgr://weight")
            )
        )

        val signedIn = widgetData.wBool("w_signed_in")
        if (!signedIn) {
            views.setViewVisibility(R.id.weight_signin, View.VISIBLE)
            views.setViewVisibility(R.id.weight_value, View.GONE)
            views.setViewVisibility(R.id.weight_delta, View.GONE)
            appWidgetManager.updateAppWidget(id, views)
            return
        }

        views.setViewVisibility(R.id.weight_signin, View.GONE)
        views.setViewVisibility(R.id.weight_value, View.VISIBLE)
        views.setViewVisibility(R.id.weight_delta, View.VISIBLE)

        val weight = widgetData.wStr("w_weight")
        val weightDelta = widgetData.wStr("w_weight_delta")
        if (weight.isNotEmpty()) {
            views.setTextViewText(R.id.weight_value, weight)
            views.setTextViewText(R.id.weight_delta, weightDelta)
        } else {
            // No weight logged yet — keep the placeholder + prompt instead of a
            // bare dash with an empty line under it.
            views.setTextViewText(R.id.weight_value, "—")
            views.setTextViewText(R.id.weight_delta, "Tap to log weight")
        }

        appWidgetManager.updateAppWidget(id, views)
    }
}
