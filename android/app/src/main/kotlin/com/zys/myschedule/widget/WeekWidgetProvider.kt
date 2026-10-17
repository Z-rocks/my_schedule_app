package com.zys.myschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.zys.myschedule.R

/**
 * 「今日课程」卡片（4×3 起步，四向可缩放，平板按 dimens 放大）。
 *
 * v2 改造（2026-10-17）：原来是 7 列 × N 行的色块网格，只有颜色没有课程名，
 * 用户看不出"第几节上什么"。现在改成**今天的课程列表**：一行一门课，
 * 给出四要素——第几节、上课时间、课程、地点；行数按卡片实际高度自适应。
 *
 * 行数算式：`(卡高 - 表头 - 上下内边距) ÷ 行高`。
 * 表头高度与行高都是 dimens（`widget_week_header_height` / `widget_row_height`），
 * 布局里写的也是同一份 dimens，所以手机 / 平板两套字号各自成立。
 * 被截断时表头右侧的"共 N 节"仍会告诉用户今天总共有几节。
 */
class WeekWidgetProvider : BaseWidgetProvider() {

    override fun render(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        snapshot: WidgetSnapshot?,
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_week)
        views.setOnClickPendingIntent(
            android.R.id.background,
            widgetLaunchIntent(context, WidgetSnapshotContract.TARGET_HOME),
        )

        if (snapshot == null) {
            showEmptyState(context, views, R.string.widget_empty_no_snapshot)
            manager.updateAppWidget(appWidgetId, views)
            return
        }

        views.setTextViewText(
            R.id.week_title,
            context.getString(
                R.string.widget_today_title,
                snapshot.todayLabel,
                snapshot.week,
            ),
        )
        // 窄卡隐藏"更新于"（见 applyUpdatedLabel）：这里 4×3 起步基本都显示。
        applyUpdatedLabel(views, manager, appWidgetId, snapshot.updatedLabel)

        val schedule = snapshot.schedule
        // 越界索引（旧快照 / 数据错位）直接丢弃，绝不让 courseTable 越界。
        val sessions = schedule.todaySessions
            .filter { it.courseIdx in schedule.courseTable.indices }

        if (!snapshot.hasSemester) {
            showEmptyState(context, views, R.string.widget_empty_no_semester)
        } else if (sessions.isEmpty()) {
            val textRes = when {
                snapshot.scheduleEmpty -> R.string.widget_empty_no_courses
                !snapshot.weekHasClass -> R.string.widget_empty_no_class_this_week
                else -> R.string.widget_empty_no_class_today
            }
            showEmptyState(context, views, textRes)
        } else {
            views.setViewVisibility(R.id.week_empty_text, View.GONE)
            views.setViewVisibility(R.id.day_list, View.VISIBLE)
            // 总数先给：列表被裁掉几行时，这里仍能说明"今天一共几节"。
            views.setTextViewText(
                R.id.week_title_right,
                context.getString(R.string.widget_day_count, sessions.size),
            )

            views.removeAllViews(R.id.day_list)
            for (session in sessions.take(maxRowsThatFit(context, manager, appWidgetId))) {
                val course = schedule.courseTable[session.courseIdx]
                val row = RemoteViews(context.packageName, R.layout.widget_week_row)
                row.setTextViewText(R.id.row_name, course.name)
                row.setInt(R.id.row_color_bar, "setBackgroundColor", course.color)
                row.setTextViewText(R.id.row_section, session.sectionText)
                if (course.room.isNotEmpty()) {
                    row.setViewVisibility(R.id.row_room, View.VISIBLE)
                    row.setTextViewText(R.id.row_room, course.room)
                } else {
                    row.setViewVisibility(R.id.row_room, View.GONE)
                }
                views.addView(R.id.day_list, row)
            }
        }

        manager.updateAppWidget(appWidgetId, views)
    }

    private fun showEmptyState(context: Context, views: RemoteViews, textRes: Int) {
        views.removeAllViews(R.id.day_list)
        views.setViewVisibility(R.id.day_list, View.GONE)
        // 空态时"共 0 节"是噪音，和中间的空态文案重复，直接留白。
        views.setTextViewText(R.id.week_title_right, "")
        views.setViewVisibility(R.id.week_empty_text, View.VISIBLE)
        views.setTextViewText(R.id.week_empty_text, context.getString(textRes))
    }

    /** 卡面能放下的行数（1..[MAX_ROWS]）。 */
    private fun maxRowsThatFit(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
    ): Int {
        val resources = context.resources
        val density = resources.displayMetrics.density
        val cardPx = (widgetHeightDp(manager, appWidgetId) * density).toInt()
        val headerPx = resources.getDimensionPixelSize(R.dimen.widget_week_header_height)
        val paddingPx = 2 * resources.getDimensionPixelSize(R.dimen.widget_card_padding_week)
        val rowPx = resources.getDimensionPixelSize(R.dimen.widget_row_height).coerceAtLeast(1)
        val rows = (cardPx - headerPx - paddingPx) / rowPx
        return rows.coerceIn(1, MAX_ROWS)
    }

    private companion object {
        /** 与 Dart `kMaxSessions` 对齐：一天最多 12 节。 */
        const val MAX_ROWS = 12
    }
}
