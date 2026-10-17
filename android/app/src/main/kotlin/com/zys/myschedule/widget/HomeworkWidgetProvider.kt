package com.zys.myschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.zys.myschedule.R

/**
 * 待交作业（2×2 / 2×4）。
 *
 * 内容：顶部"待交 N 项"+ 逾期角标；下面是未交作业列表（标题 + 课程 ·
 * 剩余天数，逾期红字）。显示条数按卡片宽度自适应（窄卡 3 条、宽卡 5 条）。
 * 全部完成显示"作业都写完啦"。点击 → 作业页。
 */
class HomeworkWidgetProvider : BaseWidgetProvider() {

    override fun render(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        snapshot: WidgetSnapshot?,
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_homework)
        views.setOnClickPendingIntent(
            android.R.id.background,
            widgetLaunchIntent(context, WidgetSnapshotContract.TARGET_HOMEWORK),
        )

        if (snapshot == null) {
            views.removeAllViews(R.id.hw_container)
            views.setViewVisibility(R.id.hw_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.hw_empty,
                context.getString(R.string.widget_empty_no_snapshot),
            )
            manager.updateAppWidget(appWidgetId, views)
            return
        }

        val homework = snapshot.homework
        views.setTextViewText(
            R.id.hw_count,
            context.getString(R.string.widget_homework_count, homework.pendingCount),
        )
        if (homework.overdueCount > 0) {
            views.setViewVisibility(R.id.hw_overdue_badge, View.VISIBLE)
            views.setTextViewText(
                R.id.hw_overdue_badge,
                context.getString(R.string.widget_homework_overdue, homework.overdueCount),
            )
        } else {
            views.setViewVisibility(R.id.hw_overdue_badge, View.GONE)
        }
        // 窄卡隐藏"更新于"，把宽度留给"待交 N 项 / 逾期 M 项"（见 applyUpdatedLabel）。
        applyUpdatedLabel(views, manager, appWidgetId, snapshot.updatedLabel)

        if (homework.items.isEmpty()) {
            views.removeAllViews(R.id.hw_container)
            views.setViewVisibility(R.id.hw_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.hw_empty,
                context.getString(R.string.widget_homework_all_done),
            )
            manager.updateAppWidget(appWidgetId, views)
            return
        }

        views.setViewVisibility(R.id.hw_empty, View.GONE)
        val limit = if (widgetWidthDp(manager, appWidgetId) >= WIDE_CARD_DP) {
            homework.items.size
        } else {
            minOf(NARROW_CARD_ITEMS, homework.items.size)
        }
        val container = R.id.hw_container
        views.removeAllViews(container)
        for (item in homework.items.take(limit)) {
            val row = RemoteViews(context.packageName, R.layout.widget_homework_row)
            row.setTextViewText(R.id.hw_title, item.title)
            val meta = buildString {
                if (item.course.isNotEmpty()) append(item.course)
                if (item.dueText.isNotEmpty()) {
                    if (isNotEmpty()) append(" · ")
                    append(item.dueText)
                }
            }
            row.setTextViewText(R.id.hw_meta, meta)
            row.setTextViewText(R.id.hw_days, item.daysLeftText)
            if (item.overdue) {
                row.setTextColor(
                    R.id.hw_days,
                    context.getColor(R.color.widget_overdue),
                )
            }
            container.let { views.addView(it, row) }
        }
        manager.updateAppWidget(appWidgetId, views)
    }

    private companion object {
        /** 窄卡（2×2）最多显示几条。 */
        const val NARROW_CARD_ITEMS = 3
    }
}
