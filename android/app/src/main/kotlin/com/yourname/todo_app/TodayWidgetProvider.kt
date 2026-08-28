package com.yourname.todo_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import kotlin.math.max
import kotlin.math.min
import org.json.JSONArray
import org.json.JSONObject

/**
 * The "Сегодня" widget: the day's tasks, tickable without opening the app.
 *
 * ## What this class is and is not
 *
 * It is a renderer, and nothing else. It never reads the database — it cannot,
 * being inflated into the launcher's process with no Dart engine anywhere near
 * it — and it never decides what a day contains. All of that is settled in
 * `lib/home_widget/today_payload.dart` and left in one JSON string in the shared
 * store, where [HomeWidgetProvider] hands it over as `widgetData`.
 *
 * The division matters for one reason above all: a tick has to be written the way
 * the app writes it, stamped and marked unsent so the sync sends it. So a tap on
 * a checkbox is not answered here either — it wakes a background Dart isolate
 * through [HomeWidgetBackgroundIntent], which calls the same DAO every screen
 * calls. Kotlin draws; Dart decides.
 *
 * ## Why the payload holds a week
 *
 * Android redraws a widget on its own schedule, and none of those moments start
 * an isolate: every half hour, at midnight, after a reboot, when it is resized.
 * A payload holding only today would therefore be wrong from the first midnight
 * the app slept through. It holds a week instead, keyed by date, and [pickDay]
 * looks up the day the clock is actually on — so a date change costs a redraw
 * and no more.
 *
 * When even that runs out — the app not opened in over a week — the widget says
 * so and asks Dart to refill it; see [requestRefresh].
 */
class TodayWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val model = parse(context, widgetData.getString(PAYLOAD_KEY, null))
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(
                widgetId,
                render(context, appWidgetManager, widgetId, model),
            )
        }
        if (model == null) requestRefresh(context)
    }

    /**
     * Redraws when the day the widget is showing stops being today.
     *
     * `updatePeriodMillis` alone would get there within half an hour, which is
     * half an hour of a widget headed "Сегодня" listing yesterday.
     * `ACTION_DATE_CHANGED` arrives at midnight itself, and the other three
     * cover a clock moved by hand, a flight, and a reboot.
     */
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED -> updateAll(context)
        }
    }

    /** Resized: a taller widget fits more rows, a shorter one fewer. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val model = parse(context, HomeWidgetPlugin.getData(context).getString(PAYLOAD_KEY, null))
        appWidgetManager.updateAppWidget(
            appWidgetId,
            render(context, appWidgetManager, appWidgetId, model),
        )
    }

    private fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java))
        if (ids.isEmpty()) return
        onUpdate(context, manager, ids, HomeWidgetPlugin.getData(context))
    }

    // -------------------------------------------------------------------------
    // Reading the payload
    // -------------------------------------------------------------------------

    /**
     * Today's slice of [raw], with the palette already chosen, or null when
     * there is nothing usable: no payload yet, a version this build does not
     * know, a week that has run out, or malformed JSON.
     *
     * Null is an ordinary answer rather than a fault. A widget outlives the
     * version of the app that put it on the home screen, and it is dropped there
     * long before the app has had a chance to write anything.
     */
    private fun parse(context: Context, raw: String?): Model? {
        if (raw.isNullOrEmpty()) return null
        return try {
            val json = JSONObject(raw)
            if (json.optInt("version") != SUPPORTED_VERSION) return null
            val day = pickDay(json.getJSONArray("days")) ?: return null
            val palettes = json.getJSONObject("palettes")
            val light = palette(palettes.getJSONObject("light"))
            val dark = palette(palettes.getJSONObject("dark"))
            val mode = json.optString("mode")
            val followsSystem = mode != "light" && mode != "dark"
            val night = if (followsSystem) isSystemDark(context) else mode == "dark"
            Model(
                day = day,
                palette = if (night) dark else light,
                light = light,
                dark = dark,
                followsSystem = followsSystem,
            )
        } catch (_: Exception) {
            null
        }
    }

    /** The entry for the current local date, or null when the week has run out. */
    private fun pickDay(days: JSONArray): Day? {
        val today = LocalDate.now().toString()
        for (index in 0 until days.length()) {
            val day = days.getJSONObject(index)
            if (day.optString("date") != today) continue

            val tasks = day.getJSONArray("tasks")
            val rows = ArrayList<Row>(tasks.length())
            for (i in 0 until tasks.length()) {
                val task = tasks.getJSONObject(i)
                rows.add(
                    Row(
                        id = task.getInt("id"),
                        title = task.optString("title"),
                        // Absent, not empty, for a task that belongs to the day
                        // without sitting at a time on it.
                        time = if (task.has("time")) task.getString("time") else null,
                        done = task.optBoolean("done"),
                        color = task.getLong("color").toInt(),
                        checkInk = task.getLong("checkInk").toInt(),
                    )
                )
            }
            return Day(
                label = day.optString("label"),
                date = today,
                total = day.optInt("total"),
                done = day.optInt("done"),
                rows = rows,
            )
        }
        return null
    }

    /** One palette of the payload, read as it was written. */
    private fun palette(values: JSONObject): Palette =
        Palette(
            card = values.getLong("card").toInt(),
            title = values.getLong("title").toInt(),
            muted = values.getLong("muted").toInt(),
            outline = values.getLong("outline").toInt(),
            accent = values.getLong("accent").toInt(),
            ring = values.getLong("ring").toInt(),
        )

    private fun isSystemDark(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    /**
     * The colours to draw with when there is no payload at all — a widget added
     * before the app has ever run.
     *
     * The only hard-coded colours in the whole feature, and the app's own
     * defaults: white or #1A1A1A for the card, the palette's violet for the
     * accent. Everything else in the widget takes its colours from the real
     * `ColorScheme`; this is what the empty state is painted with for the few
     * seconds before the first payload arrives.
     */
    private fun fallbackPalette(context: Context): Palette =
        if (isSystemDark(context)) {
            Palette(
                card = 0xFF1A1A1A.toInt(),
                title = 0xFFECECEC.toInt(),
                muted = 0xFFB0B0B0.toInt(),
                outline = 0xFF3A3A3A.toInt(),
                accent = 0xFF8B7CF6.toInt(),
                ring = 0xFF5C5C5C.toInt(),
            )
        } else {
            Palette(
                card = 0xFFFFFFFF.toInt(),
                title = 0xFF1A1A1A.toInt(),
                muted = 0xFF6B6B6B.toInt(),
                outline = 0xFFDADADA.toInt(),
                accent = 0xFF8B7CF6.toInt(),
                ring = 0xFFB9B9B9.toInt(),
            )
        }

    // -------------------------------------------------------------------------
    // Drawing
    // -------------------------------------------------------------------------

    /**
     * Sets a colour that has to follow the theme.
     *
     * On API 31 and up **both** palettes are handed over and the launcher picks
     * as it draws, which is the only way the widget can follow a system theme
     * that changes while the app is not running: a redraw needs a broadcast, and
     * the one Android sends for a configuration change is not deliverable to a
     * receiver declared in a manifest. Below that the colour is resolved here,
     * from the configuration as it is right now, and a theme switched behind the
     * app's back is corrected by the next redraw — half an hour at worst, or the
     * moment the app is next opened.
     *
     * Only used where the answer depends on the theme. A task's own colour does
     * not, and is set plainly.
     */
    private fun paint(
        views: RemoteViews,
        viewId: Int,
        method: String,
        model: Model?,
        palette: Palette,
        pick: (Palette) -> Int,
    ) {
        if (model != null &&
            model.followsSystem &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        ) {
            views.setColorInt(viewId, method, pick(model.light), pick(model.dark))
        } else {
            views.setInt(viewId, method, pick(palette))
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        model: Model?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        val palette = model?.palette ?: fallbackPalette(context)

        paint(views, R.id.widget_card, "setColorFilter", model, palette) { it.card }
        paint(views, R.id.widget_title, "setTextColor", model, palette) { it.title }
        paint(views, R.id.widget_date, "setTextColor", model, palette) { it.muted }
        paint(views, R.id.widget_calendar, "setColorFilter", model, palette) { it.muted }
        paint(views, R.id.widget_divider_top, "setColorFilter", model, palette) {
            it.outline
        }
        paint(views, R.id.widget_divider_bottom, "setColorFilter", model, palette) {
            it.outline
        }
        paint(views, R.id.widget_more, "setTextColor", model, palette) { it.muted }
        paint(views, R.id.widget_progress_label, "setTextColor", model, palette) {
            it.muted
        }
        paint(views, R.id.widget_add_label, "setTextColor", model, palette) { it.accent }
        paint(views, R.id.widget_add_icon, "setColorFilter", model, palette) { it.accent }

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
        // *reapplies* these actions to the view tree it already has, so rows
        // added last time are still there and the new ones would pile up under
        // them.
        views.removeAllViews(R.id.widget_rows)

        if (model == null) {
            views.setTextViewText(R.id.widget_date, "")
            views.setViewVisibility(R.id.widget_calendar, View.GONE)
            views.addView(
                R.id.widget_rows,
                emptyView(context, model, palette, R.string.widget_stale),
            )
            views.setViewVisibility(R.id.widget_more, View.GONE)
            hideProgress(views)
            return views
        }

        val day = model.day
        views.setViewVisibility(R.id.widget_calendar, View.VISIBLE)
        views.setTextViewText(R.id.widget_date, day.label)

        val shown = day.rows.take(capacityFor(context, appWidgetManager, widgetId, day))
        if (shown.isEmpty()) {
            views.addView(
                R.id.widget_rows,
                emptyView(context, model, palette, R.string.widget_empty),
            )
        } else {
            shown.forEach { row ->
                views.addView(
                    R.id.widget_rows,
                    rowView(context, row, model, palette, day.date),
                )
            }
        }

        // Counted against the day's real size rather than against the rows the
        // payload carries, so a day of twenty tasks says so on a widget four
        // rows tall.
        val hidden = day.total - shown.size
        if (hidden > 0) {
            views.setTextViewText(R.id.widget_more, moreLabel(context, hidden))
            views.setViewVisibility(R.id.widget_more, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_more, View.GONE)
        }

        if (day.total > 0) {
            views.setViewVisibility(R.id.widget_progress_label, View.VISIBLE)
            views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_progress_label,
                context.getString(R.string.widget_progress, day.done, day.total),
            )
            paint(views, R.id.widget_progress_track, "setColorFilter", model, palette) {
                it.outline
            }
            views.setImageViewBitmap(
                R.id.widget_progress_fill,
                progressBitmap(context, day.done, day.total),
            )
            paint(views, R.id.widget_progress_fill, "setColorFilter", model, palette) {
                it.accent
            }
        } else {
            hideProgress(views)
        }

        return views
    }

    private fun hideProgress(views: RemoteViews) {
        views.setViewVisibility(R.id.widget_progress_label, View.GONE)
        views.setViewVisibility(R.id.widget_progress, View.GONE)
    }

    private fun emptyView(
        context: Context,
        model: Model?,
        palette: Palette,
        textRes: Int,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_empty)
        views.setTextViewText(R.id.widget_empty, context.getString(textRes))
        paint(views, R.id.widget_empty, "setTextColor", model, palette) { it.muted }
        return views
    }

    /**
     * One row, with its two click targets.
     *
     * A nested [RemoteViews] per row rather than a `ListView` with an adapter,
     * and that is what buys the two targets: a collection can only carry **one**
     * pending-intent template for every item in it, so a checkbox that ticks and
     * a body that opens the app could not both exist. Nested views each carry
     * their own intents, and their ids cannot collide because each is applied to
     * the tree it was inflated into.
     *
     * The title of a done row is not dimmed. The tick is the whole of the
     * feedback, as in the design.
     */
    private fun rowView(
        context: Context,
        row: Row,
        model: Model?,
        palette: Palette,
        day: String,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_row)

        views.setInt(R.id.row_bar, "setColorFilter", row.color)
        views.setInt(R.id.row_dot, "setColorFilter", row.color)
        views.setTextViewText(R.id.row_title, row.title)
        paint(views, R.id.row_title, "setTextColor", model, palette) { it.title }
        views.setTextViewText(R.id.row_time, row.time ?: "")
        paint(views, R.id.row_time, "setTextColor", model, palette) { it.muted }

        if (row.done) {
            views.setViewVisibility(R.id.row_check_ring, View.GONE)
            views.setViewVisibility(R.id.row_check_fill, View.VISIBLE)
            views.setViewVisibility(R.id.row_check_mark, View.VISIBLE)
            views.setInt(R.id.row_check_fill, "setColorFilter", row.color)
            views.setInt(R.id.row_check_mark, "setColorFilter", row.checkInk)
        } else {
            views.setViewVisibility(R.id.row_check_ring, View.VISIBLE)
            views.setViewVisibility(R.id.row_check_fill, View.GONE)
            views.setViewVisibility(R.id.row_check_mark, View.GONE)
            paint(views, R.id.row_check_ring, "setColorFilter", model, palette) {
                it.ring
            }
        }

        // The day travels with the tap. The isolate that answers it drops a tap
        // for any day but today, which is what stops a widget drawn at 23:59 and
        // pressed at 00:01 from ticking yesterday.
        views.setOnClickPendingIntent(
            R.id.row_check,
            HomeWidgetBackgroundIntent.getBroadcast(
                context,
                widgetUri("$WIDGET_TOGGLE_PATH?task=${row.id}&day=$day"),
            ),
        )
        views.setOnClickPendingIntent(R.id.row_body, openAppIntent(context))
        return views
    }

    private fun openAppIntent(context: Context) =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            widgetUri(WIDGET_OPEN_PATH),
        )

    /**
     * How many rows fit.
     *
     * Android reports the widget's size in dp through its options bundle, in two
     * pairs: the portrait height under `MAX_HEIGHT` and the landscape one under
     * `MIN_HEIGHT`. The current orientation decides which of them is the real
     * height right now; a bundle with neither (some launchers, and a widget that
     * has never been resized) falls back to [DEFAULT_ROWS].
     */
    private fun capacityFor(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        day: Day,
    ): Int {
        val options = appWidgetManager.getAppWidgetOptions(widgetId)
        val landscape =
            context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val key =
            if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
            else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
        val heightDp = options?.getInt(key, 0) ?: 0
        if (heightDp <= 0) return min(DEFAULT_ROWS, MAX_ROWS)

        val available = heightDp - CHROME_DP
        val capacity = min(MAX_ROWS, max(1, available / ROW_DP))
        // The "ещё N" line takes a row's worth of the same space, so a day that
        // will not fit has to pay for saying so.
        if (day.total <= capacity) return capacity
        return min(MAX_ROWS, max(1, (available - MORE_DP) / ROW_DP))
    }

    /**
     * The filled part of the progress bar: white on transparent, tinted by the
     * caller.
     *
     * A bitmap because the width is the thing being shown, and RemoteViews has
     * no way to resize a view before API 31. Drawn white rather than in the
     * accent so that the tint — and with it the theme — is applied to the view
     * instead of baked into the pixels.
     *
     * A `ProgressBar` would have been the obvious view for all of this, and its
     * fill cannot be recoloured through RemoteViews on API 24 at all.
     */
    private fun progressBitmap(context: Context, done: Int, total: Int): Bitmap {
        val density = context.resources.displayMetrics.density
        val width = max(1, (PROGRESS_WIDTH_DP * density).toInt())
        val height = max(1, (PROGRESS_HEIGHT_DP * density).toInt())
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

        if (done > 0 && total > 0) {
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt() }
            val radius = height / 2f
            // Never narrower than it is tall: one task out of twenty is a dot,
            // not a sliver of a rounded end that reads as nothing at all.
            val filled = min(
                width.toFloat(),
                max(height.toFloat(), width * (done.toFloat() / total)),
            )
            canvas.drawRoundRect(RectF(0f, 0f, filled, height.toFloat()), radius, radius, paint)
        }
        return bitmap
    }

    /**
     * "ещё 2 задачи", with the Russian rule applied by hand.
     *
     * Not `<plurals>`: `getQuantityString` picks a form using the plural rules of
     * the resource's own locale, and these strings live in the default folder
     * because the app is Russian whatever the phone is set to. On an English
     * phone the rules would be English ones, and every count from two upwards
     * would come out as "ещё 3 задача".
     */
    private fun moreLabel(context: Context, count: Int): String {
        val mod100 = count % 100
        val mod10 = count % 10
        val resource = when {
            mod100 in 11..14 -> R.string.widget_more_many
            mod10 == 1 -> R.string.widget_more_one
            mod10 in 2..4 -> R.string.widget_more_few
            else -> R.string.widget_more_many
        }
        return context.getString(resource, count)
    }

    // -------------------------------------------------------------------------
    // Asking Dart to refill the payload
    // -------------------------------------------------------------------------

    /**
     * Wakes the background isolate to write a payload, for the two moments there
     * is none to draw: a widget just added while the app was closed, and a
     * stored week that has run out.
     *
     * The same receiver a checkbox tap goes through, with a URI that means
     * "refresh" instead of "toggle" — so it works whether or not the app is
     * running, which is the whole point.
     *
     * Nothing is sent when no handle has been registered yet: the app has never
     * run since it was installed, there is no Dart callback to look up, and the
     * plugin's worker would only fail. The next redraw tries again.
     */
    private fun requestRefresh(context: Context) {
        if (HomeWidgetPlugin.getDispatcherHandle(context) == 0L) return
        context.sendBroadcast(
            Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                action = BACKGROUND_ACTION
                data = widgetUri(WIDGET_REFRESH_PATH)
            }
        )
    }

    private fun widgetUri(path: String): Uri = Uri.parse("$WIDGET_SCHEME://$WIDGET_HOST$path")

    // -------------------------------------------------------------------------

    /**
     * Today, and the colours to draw it in.
     *
     * Both palettes are kept, not just the one in use: on API 31 and up they are
     * *both* handed to the launcher, which then follows the system theme by
     * itself — see [paint].
     */
    private data class Model(
        val day: Day,
        val palette: Palette,
        val light: Palette,
        val dark: Palette,
        val followsSystem: Boolean,
    )

    private data class Day(
        val date: String,
        val label: String,
        val total: Int,
        val done: Int,
        val rows: List<Row>,
    )

    private data class Row(
        val id: Int,
        val title: String,
        val time: String?,
        val done: Boolean,
        val color: Int,
        val checkInk: Int,
    )

    private data class Palette(
        val card: Int,
        val title: Int,
        val muted: Int,
        val outline: Int,
        val accent: Int,
        val ring: Int,
    )

    private companion object {
        /**
         * Where the payload is kept, and the shape it is in. Both are agreed with
         * `lib/home_widget/home_widget_bridge.dart` and
         * `lib/home_widget/today_payload.dart`; nothing checks them against each
         * other at build time.
         */
        const val PAYLOAD_KEY = "today_payload"
        const val SUPPORTED_VERSION = 1

        /** The URI vocabulary of `lib/home_widget/widget_actions.dart`. */
        const val WIDGET_SCHEME = "nook"
        const val WIDGET_HOST = "widget"
        const val WIDGET_TOGGLE_PATH = "/toggle"
        const val WIDGET_OPEN_PATH = "/open"
        const val WIDGET_CREATE_PATH = "/create"
        const val WIDGET_REFRESH_PATH = "/refresh"

        /** `home_widget`'s own action, which its receiver filters on. */
        const val BACKGROUND_ACTION = "es.antonborri.home_widget.action.BACKGROUND"

        /** Row height from `widget_today_row.xml`, in dp. */
        const val ROW_DP = 44

        /** Everything above and below the rows: padding, header, dividers, footer. */
        const val CHROME_DP = 96

        /** What the "ещё N" line costs when it is shown. */
        const val MORE_DP = 18

        const val DEFAULT_ROWS = 4
        const val MAX_ROWS = 8

        /** Kept in step with @id/widget_progress_bar in `widget_today.xml`. */
        const val PROGRESS_WIDTH_DP = 66
        const val PROGRESS_HEIGHT_DP = 7
    }
}
