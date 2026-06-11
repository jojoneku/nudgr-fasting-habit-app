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

/** Expense glance widget (Plan 039). Taps deep-link to the treasury ledger. */
class ExpenseWidgetProvider : HomeWidgetProvider() {
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
                Log.e("ExpenseWidget", "render failed", e)
            }
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        id: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_expense)
        views.setOnClickPendingIntent(
            R.id.expense_root,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("nudgr://expense")
            )
        )

        val signedIn = widgetData.wBool("w_signed_in")
        if (!signedIn) {
            views.setViewVisibility(R.id.expense_signin, View.VISIBLE)
            views.setTextViewText(R.id.expense_month, "—")
            views.setTextViewText(R.id.expense_today, "")
            appWidgetManager.updateAppWidget(id, views)
            return
        }

        views.setViewVisibility(R.id.expense_signin, View.GONE)
        // "Today" resets at midnight; the labels are peso-formatted in Dart, so
        // when the snapshot predates today just hide the line rather than
        // showing yesterday's spend as today's.
        val fresh = widgetData.wIsToday()
        val month = widgetData.wStr("w_expense_month")
        val today = if (fresh) widgetData.wStr("w_expense_today") else ""
        views.setTextViewText(R.id.expense_month, month)
        views.setTextViewText(R.id.expense_today, if (today.isNotEmpty()) "Today $today" else "")
        appWidgetManager.updateAppWidget(id, views)
    }
}
