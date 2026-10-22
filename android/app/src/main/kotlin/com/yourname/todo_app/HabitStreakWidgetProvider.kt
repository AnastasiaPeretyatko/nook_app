package com.yourname.todo_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * One habit's streak (2×2): its name, "4 дня подряд" and a dot for each day of
 * the week. Draws the same `habits_payload` as the other two habit widgets.
 *
 * Which habit it shows is chosen when the widget is added
 * ([HabitStreakConfigureActivity]) and kept per widget, by habit id, so a habit
 * added or removed does not shuffle it. A widget whose habit is gone falls back
 * to the first one rather than going blank.
 */
class HabitStreakWidgetProvider : NookWidgetProvider() {

    override val payloadKey = "habits_payload"
    override val payloadVersion = 1

    override fun hasNothing(payload: Payload) = payload.day.getJSONArray("habits").length() == 0

    override fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        payload: Payload?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_habit_streak)
        val skin = payload?.skin ?: fallbackSkin(context)
        skin.paint(views, R.id.hk_card, "setColorFilter") { it.card }
        skin.paint(views, R.id.hk_empty, "setTextColor") { it.muted }
        views.setOnClickPendingIntent(R.id.hk_card, openAppIntent(context))
        views.removeAllViews(R.id.hk_dots)

        val habit = payload?.day?.getJSONArray("habits")?.let { pick(context, widgetId, it) }
        if (payload == null || habit == null) {
            views.setViewVisibility(R.id.hk_content, View.GONE)
            views.setViewVisibility(R.id.hk_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.hk_empty,
                context.getString(if (payload == null) R.string.widget_stale else R.string.widget_habits_none),
            )
            return views
        }
        views.setViewVisibility(R.id.hk_content, View.VISIBLE)
        views.setViewVisibility(R.id.hk_empty, View.GONE)

        views.setTextViewText(R.id.hk_title, habit.optString("title"))
        views.setTextViewText(R.id.hk_number, habit.optInt("streak").toString())
        views.setTextViewText(
            R.id.hk_word,
            context.getString(R.string.widget_habit_streak_in_a_row, habit.optString("streakWord")),
        )
        skin.paint(views, R.id.hk_caption, "setTextColor") { it.muted }
        skin.paint(views, R.id.hk_title, "setTextColor") { it.title }
        skin.paint(views, R.id.hk_number, "setTextColor") { it.title }
        skin.paint(views, R.id.hk_word, "setTextColor") { it.muted }

        val week = habit.optString("week")
        for (i in 0 until minOf(7, week.length)) {
            views.addView(R.id.hk_dots, dotView(context, skin, habit, week[i]))
        }
        return views
    }

    /**
     * One day. `d` done is the habit's own colour, `t` today still open and `p`
     * partial are the accent, everything else (missed, ahead, off) the quiet grey
     * — the 2×2 design draws no difference between those.
     */
    private fun dotView(context: Context, skin: Skin, habit: JSONObject, cell: Char): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_habit_streak_dot)
        when (cell) {
            'd' -> views.setInt(R.id.dot, "setColorFilter", habit.getLong("color").toInt())
            't', 'p' -> skin.paint(views, R.id.dot, "setColorFilter") { it.accent }
            else -> skin.paint(views, R.id.dot, "setColorFilter") { it.outline }
        }
        return views
    }

    /** The habit this widget is on: the chosen one, else the first. */
    private fun pick(context: Context, widgetId: Int, habits: JSONArray): JSONObject? {
        if (habits.length() == 0) return null
        val wanted = widgetState(context).getInt(stateKey(widgetId), -1)
        return (0 until habits.length()).map { habits.getJSONObject(it) }
            .firstOrNull { it.getInt("id") == wanted } ?: habits.getJSONObject(0)
    }

    /** A removed widget leaves nothing behind in the widget's memory. */
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val state = widgetState(context).edit()
        appWidgetIds.forEach { state.remove(stateKey(it)) }
        state.apply()
    }

    companion object {
        /** Where the chosen habit's id is kept; the configure screen writes it too. */
        fun stateKey(widgetId: Int) = "habit_streak_$widgetId"
    }
}
