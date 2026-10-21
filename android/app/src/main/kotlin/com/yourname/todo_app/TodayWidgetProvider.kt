package com.yourname.todo_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import kotlin.math.max
import kotlin.math.min

/**
 * The "Сегодня" widget: the day's tasks, tickable without opening the app. One
 * design from 4×2 to 4×4 and beyond — the number of rows follows the height, and
 * the "Добавить задачу" line appears only when there is room for it. What a day
 * contains is settled in `lib/home_widget/today_payload.dart`; see
 * [NookWidgetProvider] for the division of labour.
 */
class TodayWidgetProvider : NookWidgetProvider() {

    override val payloadKey = "today_payload"
    override val payloadVersion = 1

    override fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        payload: Payload?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        val skin = payload?.skin ?: fallbackSkin(context)

        skin.paint(views, R.id.widget_card, "setColorFilter") { it.card }
        skin.paint(views, R.id.widget_title, "setTextColor") { it.title }
        skin.paint(views, R.id.widget_progress_label, "setTextColor") { it.muted }
        skin.paint(views, R.id.widget_add_disc, "setColorFilter") { it.title }
        skin.paint(views, R.id.widget_add_icon, "setColorFilter") { it.card }
        skin.paint(views, R.id.widget_add_label, "setTextColor") { it.muted }

        views.setOnClickPendingIntent(R.id.widget_header, openAppIntent(context))
        views.setOnClickPendingIntent(
            R.id.widget_add,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                widgetUri(WIDGET_CREATE_PATH),
            ),
        )

        // Mandatory, not tidiness: when the layout has not changed the launcher
        // *reapplies* these actions to the view tree it already has, so rows added
        // last time are still there and the new ones would pile up under them.
        views.removeAllViews(R.id.widget_rows)

        if (payload == null) {
            views.setViewVisibility(R.id.widget_progress_label, View.GONE)
            views.setViewVisibility(R.id.widget_add, View.GONE)
            views.addView(R.id.widget_rows, emptyView(context, skin, R.string.widget_stale))
            return views
        }

        val day = payload.day
        val total = day.optInt("total")
        val tasks = day.getJSONArray("tasks")

        val (_, heightDp) = sizeDp(context, manager, widgetId)
        val showAdd = heightDp >= ADD_MIN_HEIGHT_DP
        views.setViewVisibility(R.id.widget_add, if (showAdd) View.VISIBLE else View.GONE)
        val rows = if (heightDp <= 0) {
            DEFAULT_ROWS
        } else {
            val free = heightDp - CHROME_DP - (if (showAdd) ADD_DP else 0)
            min(MAX_ROWS, max(1, free / ROW_DP))
        }

        if (total > 0) {
            views.setViewVisibility(R.id.widget_progress_label, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_progress_label,
                context.getString(R.string.widget_progress, day.optInt("done"), total),
            )
        } else {
            views.setViewVisibility(R.id.widget_progress_label, View.GONE)
        }

        if (tasks.length() == 0) {
            views.addView(R.id.widget_rows, emptyView(context, skin, R.string.widget_empty))
        }
        for (i in 0 until min(rows, tasks.length())) {
            views.addView(R.id.widget_rows, rowView(context, skin, tasks.getJSONObject(i), payload.date))
        }
        return views
    }

    private fun emptyView(context: Context, skin: Skin, textRes: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_empty)
        views.setTextViewText(R.id.widget_empty, context.getString(textRes))
        skin.paint(views, R.id.widget_empty, "setTextColor") { it.muted }
        return views
    }

    /**
     * One row, with its two click targets.
     *
     * A nested [RemoteViews] per row rather than a `ListView` with an adapter,
     * and that is what buys the two targets: a collection carries **one**
     * pending-intent template for every item, so a checkbox that ticks and a body
     * that opens the app could not both exist.
     */
    private fun rowView(context: Context, skin: Skin, task: org.json.JSONObject, day: String): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_row)
        val color = task.getLong("color").toInt()
        val done = task.optBoolean("done")

        views.setInt(R.id.row_dot, "setColorFilter", color)
        views.setTextViewText(R.id.row_time, task.optString("time"))
        skin.paint(views, R.id.row_time, "setTextColor") { it.muted }

        // A done title is struck through and muted, as in the design. The span
        // travels inside the RemoteViews parcel; setPaintFlags would not.
        val title = SpannableString(task.optString("title"))
        if (done) title.setSpan(StrikethroughSpan(), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        views.setTextViewText(R.id.row_title, title)
        skin.paint(views, R.id.row_title, "setTextColor") { if (done) it.muted else it.title }

        if (done) {
            views.setViewVisibility(R.id.row_check_ring, View.GONE)
            views.setViewVisibility(R.id.row_check_fill, View.VISIBLE)
            views.setViewVisibility(R.id.row_check_mark, View.VISIBLE)
            views.setInt(R.id.row_check_fill, "setColorFilter", color)
            views.setInt(R.id.row_check_mark, "setColorFilter", task.getLong("checkInk").toInt())
        } else {
            views.setViewVisibility(R.id.row_check_ring, View.VISIBLE)
            views.setViewVisibility(R.id.row_check_fill, View.GONE)
            views.setViewVisibility(R.id.row_check_mark, View.GONE)
            skin.paint(views, R.id.row_check_ring, "setColorFilter") { it.ring }
        }

        // The day travels with the tap. The isolate that answers it drops a tap
        // for any day but today, which is what stops a widget drawn at 23:59 and
        // pressed at 00:01 from ticking yesterday.
        views.setOnClickPendingIntent(
            R.id.row_check,
            HomeWidgetBackgroundIntent.getBroadcast(
                context,
                widgetUri("$WIDGET_TOGGLE_PATH?task=${task.getInt("id")}&day=$day"),
            ),
        )
        views.setOnClickPendingIntent(R.id.row_body, openAppIntent(context))
        return views
    }

    private companion object {
        /** From `widget_today_row.xml` and `widget_today.xml`, in dp. */
        const val ROW_DP = 32
        const val ADD_DP = 34

        /** Padding, the header and the gap under it. */
        const val CHROME_DP = 20 + 20 + 4

        /** About four launcher cells tall: below it the add line does not fit. */
        const val ADD_MIN_HEIGHT_DP = 200

        const val DEFAULT_ROWS = 3
        const val MAX_ROWS = 8
    }
}
