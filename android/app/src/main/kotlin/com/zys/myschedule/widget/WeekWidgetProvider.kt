package com.zys.myschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.zys.myschedule.R

/**
 * 本周课表（4×2 / 4×4，平板放大）。
 *
 * 内容：7 列 × N 行的色块网格，色块颜色 = 快照课程色（Dart 侧已算好 ARGB）；
 * 今天所在列头高亮；没课的日子留空。
 *
 * 实现说明：RemoteViews 没有 GridView 式的网格控件（GridLayout 也不在
 * RemoteViews 支持列表里），用"嵌套 RemoteViews + addView"逐列拼：
 * body 容器里加 7 个列 RemoteViews，每列里加 N 个格子 RemoteViews。
 * 7×12 = 84 个小 TextView，远低于 Binder 事务上限。
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
            views.removeAllViews(R.id.days_header)
            views.removeAllViews(R.id.grid_body)
            views.setViewVisibility(R.id.week_empty_text, View.VISIBLE)
            views.setTextViewText(
                R.id.week_empty_text,
                context.getString(R.string.widget_empty_no_snapshot),
            )
            manager.updateAppWidget(appWidgetId, views)
            return
        }

        val schedule = snapshot.schedule
        views.setViewVisibility(R.id.week_empty_text, View.GONE)
        views.setTextViewText(
            R.id.week_title_right,
            context.getString(R.string.widget_week_title, schedule.week),
        )
        views.setTextViewText(R.id.updated_text, snapshot.updatedLabel)

        // 表头：周一..周日；今天那列用强调色标出。
        views.removeAllViews(R.id.days_header)
        for (day in 1..7) {
            val label = RemoteViews(context.packageName, R.layout.widget_week_day_header)
            label.setTextViewText(R.id.day_label, WEEKDAY_LABELS[day - 1])
            if (day == schedule.today) {
                label.setTextColor(
                    R.id.day_label,
                    context.getColor(R.color.widget_accent),
                )
            }
            views.addView(R.id.days_header, label)
        }

        // 网格体：7 列。行数 = 本周实际最高节次（空课表给 6 行占位）。
        val rows = when {
            schedule.maxSession in 1..12 -> schedule.maxSession
            else -> 6
        }
        views.removeAllViews(R.id.grid_body)
        for (day in 1..7) {
            val column = RemoteViews(context.packageName, R.layout.widget_week_column)
            for (session in 1..rows) {
                val courseIdx = schedule.cells.getOrNull(day - 1)?.getOrNull(session - 1) ?: -1
                val cell = RemoteViews(context.packageName, R.layout.widget_week_cell)
                if (courseIdx in schedule.courseTable.indices) {
                    cell.setInt(
                        R.id.cell,
                        "setBackgroundColor",
                        schedule.courseTable[courseIdx].color,
                    )
                }
                column.addView(R.id.cells_container, cell)
            }
            views.addView(R.id.grid_body, column)
        }

        manager.updateAppWidget(appWidgetId, views)
    }

    private companion object {
        val WEEKDAY_LABELS = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    }
}
