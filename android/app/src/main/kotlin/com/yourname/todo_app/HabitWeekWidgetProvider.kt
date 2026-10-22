package com.yourname.todo_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * One habit and its week (4×2): the name and the streak, a button that ticks
 * today, and seven circles.
 *
 * Which habit it shows is the widget's own memory, not the payload's: a tap on
 * the name moves to the next habit and the choice is kept per widget (by habit
 * id, so a habit added or removed does not shuffle it). There is no setup screen
 * to pick one up front — that would be an Activity of its own.
 */
class HabitWeekWidgetProvider : NookWidgetProvider() {

    override val payloadKey = "habits_payload"
    override val payloadVersion = 1

    override fun hasNothing(payload: Payload) = payload.day.getJSONArray("habits").length() == 0

    override fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        payload: Payload?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_habit_week)
        val skin = payload?.skin ?: fallbackSkin(context)
        skin.paint(views, R.id.hw_card, "setColorFilter") { it.card }
        skin.paint(views, R.id.hw_empty, "setTextColor") { it.muted }
        views.setOnClickPendingIntent(R.id.hw_card, openAppIntent(context))
        views.removeAllViews(R.id.hw_days)

        val habits = payload?.day?.getJSONArray("habits")
        val habit = habits?.let { pick(context, widgetId, it) }
        if (payload == null || habit == null) {
            views.setViewVisibility(R.id.hw_content, View.GONE)
            views.setViewVisibility(R.id.hw_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.hw_empty,
                context.getString(if (payload == null) R.string.widget_stale else R.string.widget_habits_none),
            )
            return views
        }
        views.setViewVisibility(R.id.hw_content, View.VISIBLE)
        views.setViewVisibility(R.id.hw_empty, View.GONE)

        views.setTextViewText(R.id.hw_title, habit.optString("title"))
        views.setTextViewText(R.id.hw_sub, habit.optString("sub"))
        skin.paint(views, R.id.hw_title, "setTextColor") { it.title }
        skin.paint(views, R.id.hw_sub, "setTextColor") { it.muted }
        views.setOnClickPendingIntent(R.id.hw_name, nextIntent(context, widgetId))

        button(context, views, skin, habit, payload.date)

        val week = habit.optString("week")
        val weekStart = payload.json.optInt("weekStart", 1)
        for (i in 0 until minOf(7, week.length)) {
            views.addView(R.id.hw_days, dayView(context, skin, habit, week[i], DAYS[(i + if (weekStart == 7) 6 else 0) % 7]))
        }
        return views
    }

    /**
     * Today's tick. Done reads "Выполнено" and un-ticks on a tap; a habit the rule
     * skips today has no button; a counter adds one ("+1 · 2/5"); a timer opens
     * the app.
     */
    private fun button(context: Context, views: RemoteViews, skin: Skin, habit: JSONObject, day: String) {
        if (!habit.optBoolean("due")) {
            views.setViewVisibility(R.id.hw_button, View.GONE)
            return
        }
        views.setViewVisibility(R.id.hw_button, View.VISIBLE)
        val done = habit.optBoolean("done")
        val kind = habit.optString("kind")
        views.setTextViewText(
            R.id.hw_button_label,
            when {
                done -> context.getString(R.string.widget_habit_done)
                kind == "counter" ->
                    context.getString(R.string.widget_habit_count, habit.optInt("count"), habit.optInt("target"))
                kind == "timer" -> context.getString(R.string.widget_habit_open)
                else -> context.getString(R.string.widget_habit_mark)
            },
        )
        skin.paint(views, R.id.hw_button_bg, "setColorFilter") { if (done) it.outline else it.title }
        skin.paint(views, R.id.hw_button_label, "setTextColor") { if (done) it.title else it.card }
        views.setOnClickPendingIntent(R.id.hw_button, habitTapIntent(context, habit, day))
    }

    /**
     * One column. `d` done, `m` missed, `t` today still open, `p` partial, `f`
     * ahead, `o` nothing planned (see `habits_payload.dart`).
     */
    private fun dayView(context: Context, skin: Skin, habit: JSONObject, cell: Char, label: String): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_habit_week_day)
        views.setTextViewText(R.id.day_label, label)
        skin.paint(views, R.id.day_label, "setTextColor") { it.muted }

        val filled = cell == 'd' || cell == 'm'
        views.setViewVisibility(R.id.day_ring, if (filled) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.day_fill, if (filled) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.day_mark, if (cell == 'd') View.VISIBLE else View.GONE)
        when (cell) {
            'd' -> {
                views.setInt(R.id.day_fill, "setColorFilter", habit.getLong("color").toInt())
                views.setInt(R.id.day_mark, "setColorFilter", habit.getLong("checkInk").toInt())
            }
            'm' -> skin.paint(views, R.id.day_fill, "setColorFilter") { it.outline }
            't', 'p' -> skin.paint(views, R.id.day_ring, "setColorFilter") { it.accent }
            else -> skin.paint(views, R.id.day_ring, "setColorFilter") { it.ring }
        }
        return views
    }

    /** The habit this widget is on: the remembered one, else the first. */
    private fun pick(context: Context, widgetId: Int, habits: JSONArray): JSONObject? {
        if (habits.length() == 0) return null
        val wanted = widgetState(context).getInt(stateKey(widgetId), -1)
        return (0 until habits.length()).map { habits.getJSONObject(it) }
            .firstOrNull { it.getInt("id") == wanted } ?: habits.getJSONObject(0)
    }

    override fun onNext(context: Context, widgetId: Int) {
        val habits = load(context)?.day?.getJSONArray("habits") ?: return
        val ids = (0 until habits.length()).map { habits.getJSONObject(it).getInt("id") }
        if (ids.isEmpty()) return
        val state = widgetState(context)
        val at = ids.indexOf(state.getInt(stateKey(widgetId), -1))
        state.edit().putInt(stateKey(widgetId), ids[(at + 1) % ids.size]).apply()
    }

    private fun stateKey(widgetId: Int) = "habit_week_$widgetId"

    private companion object {
        val DAYS = arrayOf("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")
    }
}
