package com.yourname.todo_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import org.json.JSONObject

/**
 * What every Nook home-screen widget shares: reading its payload, picking the
 * palette, and the plumbing around a redraw.
 *
 * A widget in this app is a renderer and nothing else — it never reads the
 * database, because it is inflated into the launcher's process with no Dart
 * engine near it. What it draws was settled in `lib/home_widget/` and left as one
 * JSON string per widget in the shared store; a tap goes the other way, through a
 * background Dart isolate (see `widget_actions.dart`). The payload holds a week of
 * days keyed by date and [read] picks the one the clock is on, so a midnight
 * costs a redraw and no more.
 */
abstract class NookWidgetProvider : HomeWidgetProvider() {

    /** Where the payload lives, and the shape of it this class understands. */
    protected abstract val payloadKey: String
    protected abstract val payloadVersion: Int

    /** [payload] is null when there is nothing usable: say so, do not guess. */
    internal abstract fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        payload: Payload?,
    ): RemoteViews

    /** A tap on a widget's own "next" control (page / habit), see [nextIntent]. */
    internal open fun onNext(context: Context, widgetId: Int) {}

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val payload = read(context, widgetData.getString(payloadKey, null))
        appWidgetIds.forEach {
            appWidgetManager.updateAppWidget(it, render(context, appWidgetManager, it, payload))
        }
        if (payload == null) requestRefresh(context)
    }

    /**
     * Redraws when the day a widget is showing stops being today.
     * `updatePeriodMillis` alone would get there within half an hour;
     * `ACTION_DATE_CHANGED` arrives at midnight itself, and the other three cover
     * a clock moved by hand, a flight, and a reboot.
     */
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED -> {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
                if (ids.isNotEmpty()) onUpdate(context, manager, ids, HomeWidgetPlugin.getData(context))
            }
            ACTION_NEXT -> {
                val id = intent.data?.getQueryParameter("widget")?.toIntOrNull() ?: return
                onNext(context, id)
                redraw(context, id)
            }
        }
    }

    /** Resized: the number of rows or circles that fit has changed. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        redraw(context, appWidgetId)
    }

    private fun redraw(context: Context, widgetId: Int) {
        val manager = AppWidgetManager.getInstance(context)
        manager.updateAppWidget(widgetId, render(context, manager, widgetId, load(context)))
    }

    /** The payload as it is stored right now. */
    internal fun load(context: Context): Payload? =
        read(context, HomeWidgetPlugin.getData(context).getString(payloadKey, null))

    /**
     * Today's slice of [raw] with the palette chosen, or null for no payload, a
     * version this build does not know, a week that has run out, or bad JSON.
     * Null is an ordinary answer: a widget outlives the app version that put it
     * on the home screen.
     */
    private fun read(context: Context, raw: String?): Payload? {
        if (raw.isNullOrEmpty()) return null
        return try {
            val json = JSONObject(raw)
            if (json.optInt("version") != payloadVersion) return null
            val days = json.getJSONArray("days")
            val today = LocalDate.now().toString()
            val day = (0 until days.length())
                .map { days.getJSONObject(it) }
                .firstOrNull { it.optString("date") == today } ?: return null
            val palettes = json.getJSONObject("palettes")
            val light = palette(palettes.getJSONObject("light"))
            val dark = palette(palettes.getJSONObject("dark"))
            val mode = json.optString("mode")
            val followsSystem = mode != "light" && mode != "dark"
            val night = if (followsSystem) isSystemDark(context) else mode == "dark"
            Payload(json, day, today, Skin(if (night) dark else light, light, dark, followsSystem))
        } catch (_: Exception) {
            null
        }
    }

    private fun palette(values: JSONObject) = Palette(
        card = values.getLong("card").toInt(),
        title = values.getLong("title").toInt(),
        muted = values.getLong("muted").toInt(),
        outline = values.getLong("outline").toInt(),
        accent = values.getLong("accent").toInt(),
        ring = values.getLong("ring").toInt(),
    )

    /**
     * Wakes the background isolate to write a payload, for the two moments there
     * is none to draw: a widget just added while the app was closed, and a stored
     * week that has run out. Nothing is sent before the app has ever run — there
     * is no Dart callback to look up and the worker would only fail.
     */
    private fun requestRefresh(context: Context) {
        if (HomeWidgetPlugin.getDispatcherHandle(context) == 0L) return
        context.sendBroadcast(
            Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java)
                .apply {
                    action = BACKGROUND_ACTION
                    data = widgetUri(WIDGET_REFRESH_PATH)
                }
        )
    }

    /** A broadcast back to this provider, carrying the widget it came from. */
    internal fun nextIntent(context: Context, widgetId: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            widgetId,
            Intent(context, javaClass).apply {
                action = ACTION_NEXT
                // The URI is what tells two widgets' intents apart: extras are
                // ignored when PendingIntents are matched.
                data = widgetUri("/next?widget=$widgetId")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    companion object {
        private const val ACTION_NEXT = "com.yourname.todo_app.action.NEXT"
        private const val BACKGROUND_ACTION = "es.antonborri.home_widget.action.BACKGROUND"
    }
}

/** The URI vocabulary of `lib/home_widget/widget_actions.dart`. */
internal const val WIDGET_SCHEME = "nook"
internal const val WIDGET_HOST = "widget"
internal const val WIDGET_TOGGLE_PATH = "/toggle"
internal const val WIDGET_INCREMENT_PATH = "/increment"
internal const val WIDGET_OPEN_PATH = "/open"
internal const val WIDGET_CREATE_PATH = "/create"
internal const val WIDGET_REFRESH_PATH = "/refresh"

internal fun widgetUri(path: String): Uri = Uri.parse("$WIDGET_SCHEME://$WIDGET_HOST$path")

internal fun openAppIntent(context: Context): PendingIntent =
    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, widgetUri(WIDGET_OPEN_PATH))

/**
 * What a press on a habit does, the way the app's own circle does it: a checkbox
 * is ticked, a counter gets +1 (both answered by the background isolate), and
 * anything else — a timer, or a counter already at its target — opens the app.
 */
internal fun habitTapIntent(context: Context, habit: JSONObject, day: String): PendingIntent {
    val id = habit.getInt("id")
    return when {
        habit.optString("kind") == "checkbox" ->
            HomeWidgetBackgroundIntent.getBroadcast(context, widgetUri("$WIDGET_TOGGLE_PATH?task=$id&day=$day"))
        habit.optString("kind") == "counter" && !habit.optBoolean("done") ->
            HomeWidgetBackgroundIntent.getBroadcast(context, widgetUri("$WIDGET_INCREMENT_PATH?task=$id&day=$day"))
        else -> openAppIntent(context)
    }
}

internal fun isSystemDark(context: Context): Boolean =
    (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
        Configuration.UI_MODE_NIGHT_YES

/** The widget's size in dp as the launcher reports it, 0 where it does not. */
internal fun sizeDp(context: Context, manager: AppWidgetManager, widgetId: Int): Pair<Int, Int> {
    val options = manager.getAppWidgetOptions(widgetId) ?: return 0 to 0
    val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    // The portrait width is MIN_WIDTH and the portrait height MAX_HEIGHT; the
    // landscape pair is the other way round.
    val width = options.getInt(
        if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH
        else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
        0,
    )
    val height = options.getInt(
        if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
        else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,
        0,
    )
    return width to height
}

/** Small per-widget memory the widget keeps itself: which habit, which page. */
internal fun widgetState(context: Context): SharedPreferences =
    context.getSharedPreferences("nook_widget_state", Context.MODE_PRIVATE)

/**
 * The colours to draw with when there is no payload at all — a widget added
 * before the app has ever run. The only hard-coded colours in the feature; the
 * app's own defaults.
 */
internal fun fallbackSkin(context: Context): Skin {
    val palette = if (isSystemDark(context)) {
        Palette(0xFF1A1A1A.toInt(), 0xFFECECEC.toInt(), 0xFFB0B0B0.toInt(), 0xFF3A3A3A.toInt(), 0xFF8B7CF6.toInt(), 0xFF5C5C5C.toInt())
    } else {
        Palette(0xFFFFFFFF.toInt(), 0xFF1A1A1A.toInt(), 0xFF6B6B6B.toInt(), 0xFFDADADA.toInt(), 0xFF8B7CF6.toInt(), 0xFFB9B9B9.toInt())
    }
    return Skin(palette, palette, palette, false)
}

internal data class Palette(
    val card: Int,
    val title: Int,
    val muted: Int,
    val outline: Int,
    val accent: Int,
    val ring: Int,
)

/**
 * Today's entry of a payload, and the colours to draw it in. Both palettes are
 * kept, not just the one in use: on API 31 and up they are *both* handed to the
 * launcher, which then follows a system theme that flips while the app is not
 * running — a redraw needs a broadcast, and the one Android sends for a
 * configuration change is not deliverable to a manifest receiver.
 */
internal class Payload(val json: JSONObject, val day: JSONObject, val date: String, val skin: Skin)

internal class Skin(
    private val palette: Palette,
    private val light: Palette,
    private val dark: Palette,
    private val followsSystem: Boolean,
) {
    /** Sets a colour that has to follow the theme. Below API 31 it is resolved here. */
    fun paint(views: RemoteViews, viewId: Int, method: String, pick: (Palette) -> Int) {
        if (followsSystem && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorInt(viewId, method, pick(light), pick(dark))
        } else {
            views.setInt(viewId, method, pick(palette))
        }
    }
}
