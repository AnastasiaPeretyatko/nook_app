package com.yourname.todo_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * Today's habits as a row of circles (4×1); a tap on a circle ticks it.
 *
 * It cannot scroll sideways: RemoteViews offers no horizontal scroller, and a
 * vertical one turned on its side is not something a launcher will draw. So what
 * does not fit goes onto pages, and the chevron at the end turns them — the page
 * is the widget's own memory, kept per widget.
 */
class HabitStripWidgetProvider : NookWidgetProvider() {

    override val payloadKey = "habits_payload"
    override val payloadVersion = 1

    override fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        payload: Payload?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_habit_strip)
        val skin = payload?.skin ?: fallbackSkin(context)
        skin.paint(views, R.id.hs_card, "setColorFilter") { it.card }
        skin.paint(views, R.id.hs_empty, "setTextColor") { it.muted }
        skin.paint(views, R.id.hs_next_icon, "setColorFilter") { it.muted }
        views.setOnClickPendingIntent(R.id.hs_card, openAppIntent(context))
        views.removeAllViews(R.id.hs_items)

        val all = payload?.day?.getJSONArray("habits")
        val habits = (0 until (all?.length() ?: 0)).map { all!!.getJSONObject(it) }.filter { it.optBoolean("due") }
        if (payload == null || habits.isEmpty()) {
            views.setViewVisibility(R.id.hs_content, View.GONE)
            views.setViewVisibility(R.id.hs_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.hs_empty,
                context.getString(if (payload == null) R.string.widget_stale else R.string.widget_habits_none_today),
            )
            return views
        }
        views.setViewVisibility(R.id.hs_content, View.VISIBLE)
        views.setViewVisibility(R.id.hs_empty, View.GONE)

        // As many circles as the width allows; if they do not all fit, the
        // chevron takes some of it back.
        val (widthDp, _) = sizeDp(context, manager, widgetId)
        val width = if (widthDp > 0) widthDp else DEFAULT_WIDTH_DP
        val wholeRow = maxOf(2, (width - PAD_DP) / ITEM_DP)
        val perPage = if (habits.size <= wholeRow) wholeRow else maxOf(2, (width - PAD_DP - NEXT_DP) / ITEM_DP)
        val pages = (habits.size + perPage - 1) / perPage
        val page = widgetState(context).getInt(stateKey(widgetId), 0).mod(pages)

        habits.drop(page * perPage).take(perPage).forEach {
            views.addView(R.id.hs_items, itemView(context, skin, it, payload.date))
        }

        views.setViewVisibility(R.id.hs_next, if (pages > 1) View.VISIBLE else View.GONE)
        if (pages > 1) views.setOnClickPendingIntent(R.id.hs_next, nextIntent(context, widgetId))
        return views
    }

    private fun itemView(context: Context, skin: Skin, habit: JSONObject, day: String): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_habit_strip_item)
        val done = habit.optBoolean("done")

        views.setTextViewText(R.id.item_label, habit.optString("title"))
        skin.paint(views, R.id.item_label, "setTextColor") { it.muted }
        views.setViewVisibility(R.id.item_ring, if (done) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.item_fill, if (done) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.item_mark, if (done) View.VISIBLE else View.GONE)
        if (done) {
            views.setInt(R.id.item_fill, "setColorFilter", habit.getLong("color").toInt())
            views.setInt(R.id.item_mark, "setColorFilter", habit.getLong("checkInk").toInt())
        } else {
            skin.paint(views, R.id.item_ring, "setColorFilter") { it.ring }
        }

        // A counter shows its tally in the circle until it is done.
        val counter = habit.optString("kind") == "counter" && !done
        views.setViewVisibility(R.id.item_count, if (counter) View.VISIBLE else View.GONE)
        if (counter) {
            views.setTextViewText(R.id.item_count, "${habit.optInt("count")}/${habit.optInt("target")}")
            skin.paint(views, R.id.item_count, "setTextColor") { it.title }
        }

        views.setOnClickPendingIntent(R.id.hs_item, habitTapIntent(context, habit, day))
        return views
    }

    override fun onNext(context: Context, widgetId: Int) {
        val state = widgetState(context)
        // Wrapped at render time, once the number of pages is known.
        state.edit().putInt(stateKey(widgetId), state.getInt(stateKey(widgetId), 0) + 1).apply()
    }

    private fun stateKey(widgetId: Int) = "habit_strip_page_$widgetId"

    private companion object {
        /** `widget_habit_strip_item.xml`, `widget_habit_strip.xml`, in dp. */
        const val ITEM_DP = 52
        const val PAD_DP = 20
        const val NEXT_DP = 30
        const val DEFAULT_WIDTH_DP = 250
    }
}
