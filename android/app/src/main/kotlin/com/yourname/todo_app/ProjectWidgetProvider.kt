package com.yourname.todo_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

private const val PROJECT_WIDGET_EXTRA_TAP = "project_widget_tap"
private const val PROJECT_WIDGET_EXTRA_TASK_ID = "project_widget_task_id"
private const val PROJECT_WIDGET_EXTRA_DAY = "project_widget_day"
private const val PROJECT_WIDGET_TAP_TOGGLE = "toggle"
private const val PROJECT_WIDGET_TAP_OPEN_TASK = "open_task"
private const val PROJECT_WIDGET_NO_TASK_ID = -1

/**
 * A configurable project widget.
 *
 * The selected project id is stored under this widget instance's AppWidget id;
 * all task/project data remains a Flutter-produced snapshot in the normal
 * home_widget store. Rows use a RemoteViews collection, so the launcher can
 * scroll every section and its tasks rather than truncating a short card.
 */
class ProjectWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val payload = readProjectWidgetPayload(context, widgetData.getString(PAYLOAD_KEY, null))
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, render(context, id, payload))
        }
        // Updating the card alone does not make an already-bound collection
        // ask its factory again. This call is what refreshes every visible row.
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.project_widget_rows)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val payload = readProjectWidgetPayload(
            context,
            HomeWidgetPlugin.getData(context).getString(PAYLOAD_KEY, null),
        )
        appWidgetManager.updateAppWidget(appWidgetId, render(context, appWidgetId, payload))
        appWidgetManager.notifyAppWidgetViewDataChanged(
            intArrayOf(appWidgetId),
            R.id.project_widget_rows,
        )
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        widgetState(context).edit().apply {
            appWidgetIds.forEach { removeSettings(this, it) }
        }.apply()
    }

    override fun onReceive(context: Context, intent: Intent) {
        // `HomeWidget.updateWidget` uses the regular update action too. Replacing
        // the card for that broadcast detaches the ListView's adapter, which
        // flashes the collection and loses its scroll position. A system update
        // still needs a complete RemoteViews tree, so only the plugin-marked
        // data update is applied incrementally.
        if (
            intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE &&
                intent.getBooleanExtra(HomeWidgetPlugin.TRIGGERED_FROM_HOME_WIDGET, false)
        ) {
            updateStoredPayload(context, intent)
            return
        }
        if (intent.action == ACTION_ROW_TAP) {
            when (intent.getStringExtra(PROJECT_WIDGET_EXTRA_TAP)) {
                PROJECT_WIDGET_TAP_TOGGLE -> {
                    val taskId = intent.getIntExtra(
                        PROJECT_WIDGET_EXTRA_TASK_ID,
                        PROJECT_WIDGET_NO_TASK_ID,
                    )
                    val day = intent.getStringExtra(PROJECT_WIDGET_EXTRA_DAY)
                    if (taskId != PROJECT_WIDGET_NO_TASK_ID && day != null) {
                        forwardToggle(
                            context,
                            widgetUri(
                                WIDGET_PROJECT_TOGGLE_PATH,
                                mapOf(
                                    WIDGET_TASK_PARAM to taskId.toString(),
                                    WIDGET_DAY_PARAM to day,
                                ),
                            ),
                        )
                    }
                }
                PROJECT_WIDGET_TAP_OPEN_TASK -> {
                    val taskId = intent.getIntExtra(
                        PROJECT_WIDGET_EXTRA_TASK_ID,
                        PROJECT_WIDGET_NO_TASK_ID,
                    )
                    if (taskId != PROJECT_WIDGET_NO_TASK_ID) {
                        openNook(
                            context,
                            widgetUri(
                                WIDGET_PROJECT_TASK_PATH,
                                mapOf(WIDGET_TASK_PARAM to taskId.toString()),
                            ),
                        )
                    }
                }
            }
            return
        }
        super.onReceive(context, intent)
    }

    private fun updateStoredPayload(context: Context, intent: Intent) {
        val widgetIds = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
            ?: return
        if (widgetIds.isEmpty()) return

        val manager = AppWidgetManager.getInstance(context)
        val payload = readProjectWidgetPayload(
            context,
            HomeWidgetPlugin.getData(context).getString(PAYLOAD_KEY, null),
        )
        widgetIds.forEach { widgetId ->
            // This intentionally omits setRemoteAdapter: the original adapter
            // remains bound while notifyAppWidgetViewDataChanged reloads its
            // rows in place.
            manager.partiallyUpdateAppWidget(
                widgetId,
                renderPartial(context, widgetId, payload),
            )
        }
        manager.notifyAppWidgetViewDataChanged(widgetIds, R.id.project_widget_rows)
    }

    /** Draws one specific widget, also used by the configuration activity. */
    internal fun render(
        context: Context,
        widgetId: Int,
        payload: ProjectWidgetPayloadSnapshot?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_project)
        if (renderContent(context, views, widgetId, payload)) {
            bindRowsAdapter(context, views, widgetId)
        }
        return views
    }

    /** Changes card chrome without replacing its already-bound row adapter. */
    private fun renderPartial(
        context: Context,
        widgetId: Int,
        payload: ProjectWidgetPayloadSnapshot?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_project)
        renderContent(context, views, widgetId, payload)
        return views
    }

    /** Renders the non-collection portion and reports whether rows are available. */
    private fun renderContent(
        context: Context,
        views: RemoteViews,
        widgetId: Int,
        payload: ProjectWidgetPayloadSnapshot?,
    ): Boolean {
        val settings = settings(context, widgetId)
        val skin = payload?.skinFor(context, settings.theme) ?: fallbackSkin(context)
        paintChrome(views, skin)
        applyFontSize(views, settings.fontSize)

        val projectId = settings.projectId
        val project = projectId?.let { payload?.project(it) }
        if (project == null || !project.optBoolean("available")) {
            renderUnavailable(context, views, skin, widgetId)
            return false
        }

        val total = project.optInt("total")
        val done = project.optInt("done")
        val projectUri = widgetUri(
            WIDGET_PROJECT_PATH,
            mapOf(WIDGET_PROJECT_PARAM to project.getString("id")),
        )
        val open = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            projectUri,
        )

        views.setViewVisibility(R.id.project_widget_content, View.VISIBLE)
        views.setViewVisibility(R.id.project_widget_unavailable, View.GONE)
        views.setTextViewText(R.id.project_widget_title, project.optString("name"))
        views.setTextViewText(
            R.id.project_widget_progress_label,
            context.getString(R.string.widget_project_progress, done, total),
        )
        views.setProgressBar(
            R.id.project_widget_progress,
            100,
            if (total == 0) 0 else (done * 100 / total).coerceIn(0, 100),
            false,
        )
        views.setOnClickPendingIntent(R.id.project_widget_header, open)
        views.setOnClickPendingIntent(R.id.project_widget_open, open)

        return true
    }

    private fun bindRowsAdapter(
        context: Context,
        views: RemoteViews,
        widgetId: Int,
    ) {
        val adapter = Intent(context, ProjectWidgetRowsService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            // The data URI makes this adapter instance distinct from another
            // project widget. Extras alone do not participate in Intent identity.
            data = widgetUri("/project-rows", mapOf("widget" to widgetId.toString()))
        }
        views.setRemoteAdapter(R.id.project_widget_rows, adapter)
        views.setEmptyView(R.id.project_widget_rows, R.id.project_widget_empty)
        views.setPendingIntentTemplate(
            R.id.project_widget_rows,
            PendingIntent.getBroadcast(
                context,
                widgetId,
                Intent(context, ProjectWidgetProvider::class.java).apply {
                    action = ACTION_ROW_TAP
                    data = widgetUri("/project-row", mapOf("widget" to widgetId.toString()))
                },
                collectionTemplateFlags(),
            ),
        )
    }

    private fun paintChrome(views: RemoteViews, skin: Skin) {
        skin.paint(views, R.id.project_widget_card, "setColorFilter") { it.card }
        skin.paint(views, R.id.project_widget_title, "setTextColor") { it.title }
        skin.paint(views, R.id.project_widget_progress_label, "setTextColor") { it.muted }
        skin.paint(views, R.id.project_widget_empty, "setTextColor") { it.muted }
        skin.paint(views, R.id.project_widget_unavailable_label, "setTextColor") { it.muted }
        skin.paint(views, R.id.project_widget_reconfigure, "setTextColor") { it.accent }
        skin.paint(views, R.id.project_widget_open, "setTextColor") { it.accent }
    }

    private fun applyFontSize(views: RemoteViews, fontSize: ProjectWidgetFontSize) {
        views.setTextViewTextSize(R.id.project_widget_title, TypedValue.COMPLEX_UNIT_SP, fontSize.titleSp)
        views.setTextViewTextSize(R.id.project_widget_progress_label, TypedValue.COMPLEX_UNIT_SP, fontSize.metaSp)
        views.setTextViewTextSize(R.id.project_widget_empty, TypedValue.COMPLEX_UNIT_SP, fontSize.bodySp)
        views.setTextViewTextSize(R.id.project_widget_unavailable_label, TypedValue.COMPLEX_UNIT_SP, fontSize.bodySp)
        views.setTextViewTextSize(R.id.project_widget_reconfigure, TypedValue.COMPLEX_UNIT_SP, fontSize.bodySp)
        views.setTextViewTextSize(R.id.project_widget_open, TypedValue.COMPLEX_UNIT_SP, fontSize.bodySp)
    }

    private fun renderUnavailable(
        context: Context,
        views: RemoteViews,
        skin: Skin,
        widgetId: Int,
    ) {
        views.setViewVisibility(R.id.project_widget_content, View.GONE)
        views.setViewVisibility(R.id.project_widget_unavailable, View.VISIBLE)
        views.setTextViewText(R.id.project_widget_title, context.getString(R.string.widget_project_title))
        views.setTextViewText(
            R.id.project_widget_unavailable_label,
            context.getString(R.string.widget_project_unavailable),
        )
        views.setOnClickPendingIntent(
            R.id.project_widget_reconfigure,
            configurationIntent(context, widgetId),
        )
        // A tap on the header is another natural way to change an unavailable
        // widget; useful on launchers that do not expose the widget's settings.
        views.setOnClickPendingIntent(
            R.id.project_widget_header,
            configurationIntent(context, widgetId),
        )
    }

    private fun forwardToggle(context: Context, uri: android.net.Uri) {
        // Exactly the existing checkbox channel: Flutter starts its background
        // isolate and calls TasksDao.toggleCompletion, preserving sync marks,
        // completion timestamps and subtask handling.
        context.sendBroadcast(
            Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
                action = "es.antonborri.home_widget.action.BACKGROUND"
                data = uri
            },
        )
    }

    private fun openNook(context: Context, uri: android.net.Uri) {
        try {
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri).send()
        } catch (_: PendingIntent.CanceledException) {
            // A launcher can keep a stale row while the app is updating. There
            // is no useful recovery beyond the next payload redraw.
        }
    }

    companion object {
        const val PAYLOAD_KEY = "project_widget_payload"
        const val PAYLOAD_VERSION = 2
        private const val ACTION_ROW_TAP = "com.yourname.todo_app.action.PROJECT_WIDGET_ROW_TAP"

        internal fun stateKey(widgetId: Int) = "project_widget_project_$widgetId"
        private fun themeKey(widgetId: Int) = "project_widget_theme_$widgetId"
        private fun fontSizeKey(widgetId: Int) = "project_widget_font_size_$widgetId"

        internal fun settings(context: Context, widgetId: Int) = ProjectWidgetSettings(
            projectId = widgetState(context).getString(stateKey(widgetId), null),
            theme = ProjectWidgetTheme.fromStored(
                widgetState(context).getString(themeKey(widgetId), null),
            ),
            fontSize = ProjectWidgetFontSize.fromStored(
                widgetState(context).getString(fontSizeKey(widgetId), null),
            ),
        )

        internal fun saveSettings(
            context: Context,
            widgetId: Int,
            settings: ProjectWidgetSettings,
        ) {
            widgetState(context).edit().apply {
                putString(stateKey(widgetId), settings.projectId)
                putString(themeKey(widgetId), settings.theme.storedValue)
                putString(fontSizeKey(widgetId), settings.fontSize.storedValue)
            }.apply()
        }

        private fun removeSettings(editor: SharedPreferences.Editor, widgetId: Int) {
            editor.remove(stateKey(widgetId))
            editor.remove(themeKey(widgetId))
            editor.remove(fontSizeKey(widgetId))
        }

        internal fun configurationIntent(context: Context, widgetId: Int): PendingIntent =
            PendingIntent.getActivity(
                context,
                widgetId,
                Intent(context, ProjectWidgetConfigureActivity::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                    data = widgetUri("/project-config", mapOf("widget" to widgetId.toString()))
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        /**
         * A collection row supplies a fill-in Intent at click time. On Android
         * 12+ an immutable template silently rejects that data, so this is
         * deliberately mutable only for the collection; all ordinary widget
         * launches remain immutable.
         */
        private fun collectionTemplateFlags(): Int =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_MUTABLE
                } else {
                    0
                }

        internal fun availableProjects(context: Context): List<ProjectWidgetChoice> {
            val payload = readProjectWidgetPayload(
                context,
                HomeWidgetPlugin.getData(context).getString(PAYLOAD_KEY, null),
            ) ?: return emptyList()
            val projects = payload.json.optJSONArray("projects") ?: return emptyList()
            return (0 until projects.length())
                .map { projects.getJSONObject(it) }
                .filter { it.optBoolean("available") }
                .map { ProjectWidgetChoice(it.getString("id"), it.optString("name")) }
        }
    }
}

internal data class ProjectWidgetChoice(val id: String, val name: String)

internal data class ProjectWidgetSettings(
    val projectId: String?,
    val theme: ProjectWidgetTheme,
    val fontSize: ProjectWidgetFontSize,
)

internal enum class ProjectWidgetTheme(val storedValue: String) {
    system("system"),
    light("light"),
    dark("dark");

    companion object {
        fun fromStored(value: String?) = entries.firstOrNull { it.storedValue == value } ?: system
    }
}

internal enum class ProjectWidgetFontSize(
    val storedValue: String,
    val titleSp: Float,
    val metaSp: Float,
    val bodySp: Float,
    val sectionSp: Float,
) {
    small("small", 14f, 11f, 12f, 11f),
    standard("standard", 15f, 12f, 13f, 12f),
    large("large", 17f, 14f, 15f, 14f);

    companion object {
        fun fromStored(value: String?) = entries.firstOrNull { it.storedValue == value } ?: standard
    }
}

/** A collection service. Android owns this separately from the card renderer. */
class ProjectWidgetRowsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory =
        ProjectWidgetRowsFactory(
            applicationContext,
            intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            ),
        )
}

private class ProjectWidgetRowsFactory(
    private val context: Context,
    private val widgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {
    private var payload: ProjectWidgetPayloadSnapshot? = null
    private var rows = emptyList<ProjectWidgetRow>()

    override fun onCreate() = onDataSetChanged()

    override fun onDataSetChanged() {
        payload = readProjectWidgetPayload(
            context,
            HomeWidgetPlugin.getData(context).getString(ProjectWidgetProvider.PAYLOAD_KEY, null),
        )
        val id = ProjectWidgetProvider.settings(context, widgetId).projectId
        val project = id?.let { payload?.project(it) }
        rows = projectRows(project)
    }

    override fun onDestroy() {
        rows = emptyList()
        payload = null
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews? {
        val row = rows.getOrNull(position) ?: return null
        val settings = ProjectWidgetProvider.settings(context, widgetId)
        val skin = payload?.skinFor(context, settings.theme) ?: fallbackSkin(context)
        if (row.isSection) {
            return RemoteViews(context.packageName, R.layout.widget_project_section).apply {
                setTextViewText(R.id.project_section_name, row.value.optString("name"))
                setTextViewTextSize(
                    R.id.project_section_name,
                    TypedValue.COMPLEX_UNIT_SP,
                    settings.fontSize.sectionSp,
                )
                skin.paint(this, R.id.project_section_name, "setTextColor") { it.muted }
            }
        }
        val task = row.value
        val views = RemoteViews(context.packageName, R.layout.widget_project_row)
        val done = task.optBoolean("done")
        val color = task.optLong("color").toInt()
        val title = SpannableString(task.optString("title"))
        if (done) {
            title.setSpan(StrikethroughSpan(), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        views.setTextViewText(R.id.project_row_body, title)
        views.setTextViewTextSize(
            R.id.project_row_body,
            TypedValue.COMPLEX_UNIT_SP,
            settings.fontSize.bodySp,
        )
        skin.paint(views, R.id.project_row_body, "setTextColor") { if (done) it.muted else it.title }
        if (done) {
            views.setViewVisibility(R.id.project_row_check_ring, View.GONE)
            views.setViewVisibility(R.id.project_row_check_fill, View.VISIBLE)
            views.setViewVisibility(R.id.project_row_check_mark, View.VISIBLE)
            views.setInt(R.id.project_row_check_fill, "setColorFilter", color)
            views.setInt(R.id.project_row_check_mark, "setColorFilter", task.optLong("checkInk").toInt())
        } else {
            views.setViewVisibility(R.id.project_row_check_ring, View.VISIBLE)
            views.setViewVisibility(R.id.project_row_check_fill, View.GONE)
            views.setViewVisibility(R.id.project_row_check_mark, View.GONE)
            skin.paint(views, R.id.project_row_check_ring, "setColorFilter") { it.ring }
        }

        val taskId = task.getInt("id")
        views.setOnClickFillInIntent(
            R.id.project_row_check,
            Intent().apply {
                putExtra(PROJECT_WIDGET_EXTRA_TAP, PROJECT_WIDGET_TAP_TOGGLE)
                putExtra(PROJECT_WIDGET_EXTRA_TASK_ID, taskId)
                putExtra(PROJECT_WIDGET_EXTRA_DAY, task.getString("day"))
            },
        )
        views.setOnClickFillInIntent(
            R.id.project_row_body,
            Intent().apply {
                putExtra(PROJECT_WIDGET_EXTRA_TAP, PROJECT_WIDGET_TAP_OPEN_TASK)
                putExtra(PROJECT_WIDGET_EXTRA_TASK_ID, taskId)
            },
        )
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long {
        val row = rows.getOrNull(position) ?: return position.toLong()
        return if (row.isSection) {
            -row.value.optString("id").hashCode().toLong() - 1
        } else {
            row.value.optLong("id")
        }
    }

    override fun hasStableIds(): Boolean = true
}

private data class ProjectWidgetRow(val isSection: Boolean, val value: JSONObject)

private fun projectRows(project: JSONObject?): List<ProjectWidgetRow> {
    if (project?.optBoolean("available") != true) return emptyList()
    val sections = project.optJSONArray("sections") ?: return emptyList()
    return buildList {
        for (index in 0 until sections.length()) {
            val section = sections.optJSONObject(index) ?: continue
            add(ProjectWidgetRow(isSection = true, value = section))
            val tasks = section.optJSONArray("tasks") ?: continue
            for (taskIndex in 0 until tasks.length()) {
                tasks.optJSONObject(taskIndex)?.let { task ->
                    add(ProjectWidgetRow(isSection = false, value = task))
                }
            }
        }
    }
}

/** The native subset of ProjectWidgetPayload, with the current palette chosen. */
internal class ProjectWidgetPayloadSnapshot(
    val json: JSONObject,
    val skin: Skin,
    private val light: Palette,
    private val dark: Palette,
) {
    fun skinFor(context: Context, theme: ProjectWidgetTheme): Skin {
        val night = when (theme) {
            ProjectWidgetTheme.system -> isSystemDark(context)
            ProjectWidgetTheme.light -> false
            ProjectWidgetTheme.dark -> true
        }
        return Skin(if (night) dark else light, light, dark, theme == ProjectWidgetTheme.system)
    }

    fun project(id: String): JSONObject? {
        val projects = json.optJSONArray("projects") ?: return null
        return (0 until projects.length())
            .map { projects.getJSONObject(it) }
            .firstOrNull { it.optString("id") == id }
    }
}

internal fun readProjectWidgetPayload(
    context: Context,
    raw: String?,
): ProjectWidgetPayloadSnapshot? {
    if (raw.isNullOrEmpty()) return null
    return try {
        val json = JSONObject(raw)
        if (json.optInt("version") != ProjectWidgetProvider.PAYLOAD_VERSION) return null
        val palettes = json.getJSONObject("palettes")
        val light = projectWidgetPalette(palettes.getJSONObject("light"))
        val dark = projectWidgetPalette(palettes.getJSONObject("dark"))
        val mode = json.optString("mode")
        val followsSystem = mode != "light" && mode != "dark"
        val night = if (followsSystem) isSystemDark(context) else mode == "dark"
        ProjectWidgetPayloadSnapshot(
            json,
            Skin(if (night) dark else light, light, dark, followsSystem),
            light,
            dark,
        )
    } catch (_: Exception) {
        null
    }
}

private fun projectWidgetPalette(values: JSONObject) = Palette(
    card = values.getLong("card").toInt(),
    title = values.getLong("title").toInt(),
    muted = values.getLong("muted").toInt(),
    outline = values.getLong("outline").toInt(),
    accent = values.getLong("accent").toInt(),
    ring = values.getLong("ring").toInt(),
)
