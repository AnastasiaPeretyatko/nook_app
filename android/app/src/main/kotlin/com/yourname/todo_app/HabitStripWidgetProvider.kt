package com.yourname.todo_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import kotlin.math.roundToInt
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

    override fun hasNothing(payload: Payload) = payload.day.getJSONArray("habits").length() == 0

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

        // As many habits as the width allows; if they do not all fit, the
        // chevron takes some of it back.
        val (widthDp, heightDp) = sizeDp(context, manager, widgetId)
        val width = if (widthDp > 0) widthDp else DEFAULT_WIDTH_DP
        val circle = circleDp(width, heightDp, habits.size)
        val item = if (circle == CIRCLE_DP) ITEM_DP else circle + ITEM_EXTRA_DP
        val wholeRow = maxOf(2, fits(width - PAD_DP, item))
        val perPage = if (habits.size <= wholeRow) wholeRow else maxOf(2, fits(width - PAD_DP - NEXT_DP, item))
        val pages = (habits.size + perPage - 1) / perPage
        val page = widgetState(context).getInt(stateKey(widgetId), 0).mod(pages)

        // Fixed-width habits pinned to the left edge, a fixed gap between them.
        habits.drop(page * perPage).take(perPage).forEachIndexed { i, habit ->
            if (i > 0) views.addView(R.id.hs_items, gapView(context))
            views.addView(R.id.hs_items, itemView(context, skin, habit, payload.date, circle))
        }

        views.setViewVisibility(R.id.hs_next, if (pages > 1) View.VISIBLE else View.GONE)
        if (pages > 1) views.setOnClickPendingIntent(R.id.hs_next, nextIntent(context, widgetId))
        return views
    }

    private fun gapView(context: Context) = RemoteViews(context.packageName, R.layout.widget_habit_strip_gap)

    /** How many habits [item] dp wide fit into [dp], with at least [MIN_GAP_DP] between them. */
    private fun fits(dp: Int, item: Int) = (dp + MIN_GAP_DP) / (item + MIN_GAP_DP)

    /**
     * The circle's diameter: as big as the widget's height allows (the card is
     * taller than the content on most launchers), but never so big that the habits
     * shown stop fitting side by side — up to five are counted, more go on pages —
     * and never under the design's 40.
     *
     * shortcut: the size of a layout can only be changed from API 31
     * (`setViewLayoutWidth`), so older phones keep 40 — upgrade by shipping a
     * second item layout if those phones matter.
     */
    private fun circleDp(width: Int, height: Int, habits: Int): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || height <= 0) return CIRCLE_DP
        val n = habits.coerceIn(1, 5)
        val byWidth = (width - PAD_DP - (n - 1) * MIN_GAP_DP) / n - ITEM_EXTRA_DP
        val byHeight = height - CHROME_DP
        return minOf(byWidth, byHeight).coerceIn(CIRCLE_DP, MAX_CIRCLE_DP)
    }

    private fun itemView(context: Context, skin: Skin, habit: JSONObject, day: String, circle: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_habit_strip_item)
        val done = habit.optBoolean("done")

        if (circle != CIRCLE_DP) {
            val dip = TypedValue.COMPLEX_UNIT_DIP
            views.setViewLayoutWidth(R.id.hs_item, (circle + ITEM_EXTRA_DP).toFloat(), dip)
            views.setViewLayoutWidth(R.id.item_circle, circle.toFloat(), dip)
            views.setViewLayoutHeight(R.id.item_circle, circle.toFloat(), dip)
            views.setViewLayoutWidth(R.id.item_mark, circle * 0.4f, dip)
            views.setViewLayoutHeight(R.id.item_mark, circle * 0.4f, dip)
        }

        views.setTextViewText(R.id.item_label, habit.optString("title"))
        skin.paint(views, R.id.item_label, "setTextColor") { it.muted }
        views.setViewVisibility(R.id.item_ring, if (done) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.item_fill, if (done) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.item_mark, if (done) View.VISIBLE else View.GONE)
        if (done) {
            // The darker tone of the habit's colour, as the app's own done circle.
            skin.paintPair(views, R.id.item_fill, "setColorFilter", habit.getLong("fill").toInt(), habit.getLong("fillDark").toInt())
            skin.paintPair(views, R.id.item_mark, "setColorFilter", habit.getLong("fillInk").toInt(), habit.getLong("fillInkDark").toInt())
        } else {
            skin.paint(views, R.id.item_ring, "setColorFilter") { it.ring }
        }

        // A counter shows its tally in the circle, and its progress as an arc
        // along the rim that grows clockwise, until it is done.
        val counter = habit.optString("kind") == "counter" && !done
        views.setViewVisibility(R.id.item_count, if (counter) View.VISIBLE else View.GONE)
        val count = habit.optInt("count")
        val target = habit.optInt("target")
        val progress = counter && count > 0 && target > 0
        views.setViewVisibility(R.id.item_progress, if (progress) View.VISIBLE else View.GONE)
        if (counter) {
            views.setTextViewText(R.id.item_count, "$count/$target")
            skin.paint(views, R.id.item_count, "setTextColor") { it.title }
        }
        if (progress) {
            views.setImageViewBitmap(R.id.item_progress, progressArc(context, count.toFloat() / target, circle))
            skin.paintPair(views, R.id.item_progress, "setColorFilter", habit.getLong("fill").toInt(), habit.getLong("fillDark").toInt())
        }

        views.setOnClickPendingIntent(R.id.hs_item, habitTapIntent(context, habit, day))
        return views
    }

    /**
     * A white arc over the empty ring, [fraction] of the way round from twelve
     * o'clock. White on purpose: the colour is a tint set per theme afterwards, so
     * the bitmap does not have to know which theme the launcher is in. The
     * geometry is that of `widget_habit_ring.xml` (radius 19 and stroke 2 on a 40
     * grid), so the arc lies exactly on the ring.
     */
    private fun progressArc(context: Context, fraction: Float, circle: Int): Bitmap {
        val size = (circle * context.resources.displayMetrics.density).roundToInt()
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val unit = size / 40f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 2f * unit
            strokeCap = Paint.Cap.ROUND
        }
        val c = 20f * unit
        val r = 19f * unit
        Canvas(bitmap).drawArc(RectF(c - r, c - r, c + r, c + r), -90f, 360f * fraction.coerceIn(0f, 1f), false, paint)
        return bitmap
    }

    override fun onNext(context: Context, widgetId: Int) {
        val state = widgetState(context)
        // Wrapped at render time, once the number of pages is known.
        state.edit().putInt(stateKey(widgetId), state.getInt(stateKey(widgetId), 0) + 1).apply()
    }

    private fun stateKey(widgetId: Int) = "habit_strip_page_$widgetId"

    private companion object {
        /**
         * `widget_habit_strip_item.xml` and `widget_habit_strip.xml`, in dp: the
         * design's circle with its 56dp item, the most the circle grows to, what an
         * item adds around a bigger circle, the row's side padding (2 each), the gap between habits,
         * and what the vertical padding, the label and the breathing room take.
         */
        const val CIRCLE_DP = 40
        const val ITEM_DP = 56
        const val MAX_CIRCLE_DP = 64
        const val ITEM_EXTRA_DP = 12
        const val PAD_DP = 4
        const val MIN_GAP_DP = 9
        const val CHROME_DP = 33
        const val NEXT_DP = 30
        const val DEFAULT_WIDTH_DP = 250
    }
}
