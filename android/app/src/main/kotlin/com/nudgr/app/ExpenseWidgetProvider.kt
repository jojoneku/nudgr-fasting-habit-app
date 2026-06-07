package com.nudgr.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
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
            val views = RemoteViews(context.packageName, R.layout.widget_expense)
            views.setOnClickPendingIntent(
                R.id.expense_root,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("nudgr://expense")
                )
            )

            val signedIn = widgetData.getBoolean("w_signed_in", false)
            if (!signedIn) {
                views.setViewVisibility(R.id.expense_signin, View.VISIBLE)
                views.setTextViewText(R.id.expense_month, "—")
                views.setTextViewText(R.id.expense_today, "")
                appWidgetManager.updateAppWidget(id, views)
                continue
            }

            views.setViewVisibility(R.id.expense_signin, View.GONE)
            val month = widgetData.getString("w_expense_month", "") ?: ""
            val today = widgetData.getString("w_expense_today", "") ?: ""
            views.setTextViewText(R.id.expense_month, month)
            views.setTextViewText(R.id.expense_today, if (today.isNotEmpty()) "Today $today" else "")
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
