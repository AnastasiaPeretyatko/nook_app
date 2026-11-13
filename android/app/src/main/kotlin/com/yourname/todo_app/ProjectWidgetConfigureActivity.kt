package com.yourname.todo_app

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

/** Full-screen settings for one project widget instance. */
class ProjectWidgetConfigureActivity : Activity() {
    private lateinit var preview: FrameLayout
    private lateinit var projectValue: TextView
    private lateinit var themeValue: TextView
    private lateinit var fontSizeValue: TextView
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var original: ProjectWidgetSettings? = null
    private var draft: ProjectWidgetSettings? = null
    private var confirmed = false
    private var projects = emptyList<ProjectWidgetChoice>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        setContentView(R.layout.activity_project_widget_configure)

        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        preview = findViewById(R.id.project_widget_config_preview)
        projectValue = findViewById(R.id.project_widget_config_project_value)
        themeValue = findViewById(R.id.project_widget_config_theme_value)
        fontSizeValue = findViewById(R.id.project_widget_config_font_size_value)
        findViewById<View>(R.id.project_widget_config_confirm).setOnClickListener { confirm() }
        findViewById<View>(R.id.project_widget_config_project).setOnClickListener { chooseProject() }
        findViewById<View>(R.id.project_widget_config_theme).setOnClickListener { chooseTheme() }
        findViewById<View>(R.id.project_widget_config_font_size).setOnClickListener { chooseFontSize() }

        projects = ProjectWidgetProvider.availableProjects(this)
        original = ProjectWidgetProvider.settings(this, widgetId)
        draft = original
        refresh()
    }

    override fun onDestroy() {
        if (!confirmed && widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            original?.let { ProjectWidgetProvider.saveSettings(this, widgetId, it) }
        }
        super.onDestroy()
    }

    private fun chooseProject() {
        if (projects.isEmpty()) return
        val selected = projects.indexOfFirst { it.id == draft?.projectId }.coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle(R.string.widget_project_setting_project)
            .setSingleChoiceItems(projects.map { it.name }.toTypedArray(), selected) { dialog, which ->
                update(draft!!.copy(projectId = projects[which].id))
                dialog.dismiss()
            }
            .show()
    }

    private fun chooseTheme() {
        val values = ProjectWidgetTheme.entries
        AlertDialog.Builder(this)
            .setTitle(R.string.widget_project_setting_theme)
            .setSingleChoiceItems(
                values.map { getString(themeLabel(it)) }.toTypedArray(),
                values.indexOf(draft!!.theme),
            ) { dialog, which ->
                update(draft!!.copy(theme = values[which]))
                dialog.dismiss()
            }
            .show()
    }

    private fun chooseFontSize() {
        val values = ProjectWidgetFontSize.entries
        AlertDialog.Builder(this)
            .setTitle(R.string.widget_project_setting_font_size)
            .setSingleChoiceItems(
                values.map { getString(fontSizeLabel(it)) }.toTypedArray(),
                values.indexOf(draft!!.fontSize),
            ) { dialog, which ->
                update(draft!!.copy(fontSize = values[which]))
                dialog.dismiss()
            }
            .show()
    }

    private fun update(settings: ProjectWidgetSettings) {
        draft = settings
        // The provider and RemoteViews factory share this temporary state. It
        // is restored from [original] unless the user confirms the screen.
        ProjectWidgetProvider.saveSettings(this, widgetId, settings)
        refresh()
    }

    private fun refresh() {
        val settings = draft ?: return
        projectValue.text = projects.firstOrNull { it.id == settings.projectId }?.name
            ?: getString(R.string.widget_project_setting_project_none)
        themeValue.text = getString(themeLabel(settings.theme))
        fontSizeValue.text = getString(fontSizeLabel(settings.fontSize))

        preview.removeAllViews()
        val payload = readProjectWidgetPayload(
            this,
            HomeWidgetPlugin.getData(this).getString(ProjectWidgetProvider.PAYLOAD_KEY, null),
        )
        preview.addView(
            buildPreview(payload, settings),
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    /** Native preview: RemoteViews collection adapters only work in an AppWidget host. */
    private fun buildPreview(
        payload: ProjectWidgetPayloadSnapshot?,
        settings: ProjectWidgetSettings,
    ): View {
        val skin = payload?.skinFor(this, settings.theme) ?: fallbackSkin(this)
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = roundedBackground(skin.color { it.card }, 24)
        }
        val project = settings.projectId?.let { payload?.project(it) }
        if (project == null || !project.optBoolean("available")) {
            card.addView(previewText(getString(R.string.widget_project_setting_project_none), skin.color { it.muted }, settings.fontSize.bodySp))
            return card
        }

        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(previewText(project.optString("name"), skin.color { it.title }, settings.fontSize.titleSp), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(previewText(
            getString(R.string.widget_project_progress, project.optInt("done"), project.optInt("total")),
            skin.color { it.muted },
            settings.fontSize.metaSp,
        ))
        card.addView(header)

        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        project.optJSONArray("sections")?.let { sections ->
            for (index in 0 until sections.length()) {
                val section = sections.optJSONObject(index) ?: continue
                list.addView(previewText(section.optString("name"), skin.color { it.muted }, settings.fontSize.sectionSp).apply {
                    setPadding(0, dp(7), 0, dp(2))
                })
                section.optJSONArray("tasks")?.let { tasks ->
                    for (taskIndex in 0 until tasks.length()) {
                        tasks.optJSONObject(taskIndex)?.let { task -> list.addView(previewTask(task, skin, settings.fontSize)) }
                    }
                }
            }
        }
        card.addView(ScrollView(this).apply { addView(list) }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        return card
    }

    private fun previewTask(task: JSONObject, skin: Skin, fontSize: ProjectWidgetFontSize): View = LinearLayout(this).apply {
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(34)
        val done = task.optBoolean("done")
        addView(previewText(if (done) "✓" else "○", if (done) task.optInt("color") else skin.color { it.ring }, fontSize.bodySp).apply {
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(dp(28), dp(34)))
        addView(previewText(task.optString("title"), if (done) skin.color { it.muted } else skin.color { it.title }, fontSize.bodySp).apply {
            ellipsize = TextUtils.TruncateAt.END
            maxLines = 1
            if (done) paintFlags = paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
    }

    private fun previewText(text: String, color: Int, sizeSp: Float) = TextView(this).apply {
        this.text = text
        setTextColor(color)
        textSize = sizeSp
        fontFeatureSettings = "kern"
        includeFontPadding = false
    }

    private fun roundedBackground(color: Int, radiusDp: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp).toFloat()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private fun confirm() {
        val settings = draft ?: return
        if (settings.projectId == null) return
        ProjectWidgetProvider.saveSettings(this, widgetId, settings)
        val manager = AppWidgetManager.getInstance(this)
        val provider = ProjectWidgetProvider()
        val payload = readProjectWidgetPayload(
            this,
            HomeWidgetPlugin.getData(this).getString(ProjectWidgetProvider.PAYLOAD_KEY, null),
        )
        manager.updateAppWidget(widgetId, provider.render(this, widgetId, payload))
        manager.notifyAppWidgetViewDataChanged(intArrayOf(widgetId), R.id.project_widget_rows)
        confirmed = true
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        finish()
    }

    private fun themeLabel(theme: ProjectWidgetTheme) = when (theme) {
        ProjectWidgetTheme.system -> R.string.widget_project_theme_system
        ProjectWidgetTheme.light -> R.string.widget_project_theme_light
        ProjectWidgetTheme.dark -> R.string.widget_project_theme_dark
    }

    private fun fontSizeLabel(size: ProjectWidgetFontSize) = when (size) {
        ProjectWidgetFontSize.small -> R.string.widget_project_font_small
        ProjectWidgetFontSize.standard -> R.string.widget_project_font_standard
        ProjectWidgetFontSize.large -> R.string.widget_project_font_large
    }
}
