package com.nudgr.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
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
                continue
            }

            views.setViewVisibility(R.id.weight_signin, View.GONE)
            views.setViewVisibility(R.id.weight_value, View.VISIBLE)
            views.setViewVisibility(R.id.weight_delta, View.VISIBLE)

            val weight = widgetData.wStr("w_weight")
            val weightDelta = widgetData.wStr("w_weight_delta")
            views.setTextViewText(R.id.weight_value, if (weight.isNotEmpty()) weight else "—")
            views.setTextViewText(R.id.weight_delta, weightDelta)

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
