package com.nudgr.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Quests glance widget. Shows today's done/total and the next quest, with an
 * inline ✓ that completes it via a background action (queued + applied on next
 * app foreground); the card deep-links to quests.
 */
class QuestWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_quest)

            views.setOnClickPendingIntent(
                R.id.quest_root,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("nudgr://quests")
                )
            )

            val signedIn = widgetData.wBool("w_signed_in")
            if (!signedIn) {
                views.setViewVisibility(R.id.quest_signin, View.VISIBLE)
                views.setViewVisibility(R.id.quest_count, View.GONE)
                views.setViewVisibility(R.id.quest_next_row, View.GONE)
                appWidgetManager.updateAppWidget(id, views)
                continue
            }

            views.setViewVisibility(R.id.quest_signin, View.GONE)
            views.setViewVisibility(R.id.quest_count, View.VISIBLE)
            views.setViewVisibility(R.id.quest_next_row, View.VISIBLE)

            val done = widgetData.wLong("w_quests_done")
            val total = widgetData.wLong("w_quests_total")
            val next = widgetData.wStr("w_next_quest")
            val nextId = widgetData.wLong("w_next_quest_id", -1L)
            views.setTextViewText(R.id.quest_count, "$done/$total")
            views.setTextViewText(R.id.quest_next, if (next.isNotEmpty()) next else "All done")

            if (nextId >= 0) {
                views.setViewVisibility(R.id.btn_quest_done, View.VISIBLE)
                views.setOnClickPendingIntent(
                    R.id.btn_quest_done,
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context, Uri.parse("nudgr://completequest?id=$nextId")
                    )
                )
            } else {
                views.setViewVisibility(R.id.btn_quest_done, View.GONE)
            }

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
