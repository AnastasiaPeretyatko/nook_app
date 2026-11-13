package com.yourname.todo_app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Picker shown each time the user adds (or reconfigures) a project widget.
 *
 * It reads Flutter's existing local project mirror from the widget payload;
 * selecting an item persists only its id under this particular app-widget id.
 * Two widgets can therefore point at different projects without duplicating
 * their task data.
 */
class ProjectWidgetConfigureActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        title = getString(R.string.widget_project_choose)

        val widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val projects = ProjectWidgetProvider.availableProjects(this)
        if (projects.isEmpty()) {
            Toast.makeText(this, R.string.widget_project_no_projects, Toast.LENGTH_LONG).show()
            finish()
            return
        }

        val list = ListView(this)
        list.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_list_item_1,
            projects.map { it.name },
        )
        list.setOnItemClickListener { _, _, position, _ ->
            widgetState(this).edit()
                .putString(ProjectWidgetProvider.stateKey(widgetId), projects[position].id)
                .apply()
            val manager = AppWidgetManager.getInstance(this)
            val provider = ProjectWidgetProvider()
            val payload = readProjectWidgetPayload(
                this,
                HomeWidgetPlugin.getData(this).getString(ProjectWidgetProvider.PAYLOAD_KEY, null),
            )
            manager.updateAppWidget(widgetId, provider.render(this, widgetId, payload))
            manager.notifyAppWidgetViewDataChanged(
                intArrayOf(widgetId),
                R.id.project_widget_rows,
            )
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
            finish()
        }
        setContentView(list)
    }
}
