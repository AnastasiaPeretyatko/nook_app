package com.yourname.todo_app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.Toast

/**
 * Shown by the launcher when a "Серия привычки" widget is dropped on the home
 * screen (and again from its settings, `reconfigurable`): the list of habits, a
 * tap picks one.
 *
 * Native on purpose — the list comes from the stored `habits_payload`, so no
 * Flutter engine has to start for it. The launcher throws the widget away unless
 * this activity ends with `RESULT_OK` and the widget id, so the result is
 * "cancelled" from the first line and only a pick changes it.
 */
class HabitStreakConfigureActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        title = getString(R.string.widget_habit_streak_choose)

        val widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val provider = HabitStreakWidgetProvider()
        val habits = provider.load(this)?.day?.getJSONArray("habits")
        val items = (0 until (habits?.length() ?: 0)).map { habits!!.getJSONObject(it) }
        if (items.isEmpty()) {
            // The app has never run, or has no habits: nothing to choose from.
            Toast.makeText(this, R.string.widget_habit_streak_no_habits, Toast.LENGTH_LONG).show()
            finish()
            return
        }

        val list = ListView(this)
        list.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_list_item_1,
            items.map { it.optString("title") },
        )
        list.setOnItemClickListener { _, _, position, _ ->
            widgetState(this).edit()
                .putInt(HabitStreakWidgetProvider.stateKey(widgetId), items[position].getInt("id"))
                .apply()
            // The launcher waits for this first draw; nothing else sends it.
            val manager = AppWidgetManager.getInstance(this)
            manager.updateAppWidget(widgetId, provider.render(this, manager, widgetId, provider.load(this)))
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
            finish()
        }
        setContentView(list)
    }
}
