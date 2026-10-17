package com.zys.myschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.zys.myschedule.R

/**
 * 近期考试（2×2 / 2×4）。
 *
 * 内容：顶部"N 场待考"；最近一场考试大字卡片（科目 · 倒计时 · 开考时间 ·
 * 考场）；下面是其余近期考试小行。无考试显示"近期无考试"。点击 → 考试页。
 */
class ExamWidgetProvider : BaseWidgetProvider() {

    override fun render(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        snapshot: WidgetSnapshot?,
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_exam)
        views.setOnClickPendingIntent(
            android.R.id.background,
            widgetLaunchIntent(context, WidgetSnapshotContract.TARGET_EXAM),
        )

        if (snapshot == null) {
            views.setViewVisibility(R.id.exam_next_block, View.GONE)
            views.removeAllViews(R.id.exam_list_container)
            views.setViewVisibility(R.id.exam_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.exam_empty,
                context.getString(R.string.widget_empty_no_snapshot),
            )
            manager.updateAppWidget(appWidgetId, views)
            return
        }

        val exam = snapshot.exam
        views.setTextViewText(
            R.id.exam_count,
            context.getString(R.string.widget_exam_count, exam.upcomingCount),
        )
        applyUpdatedLabel(views, manager, appWidgetId, snapshot.updatedLabel)

        if (exam.items.isEmpty()) {
            views.setViewVisibility(R.id.exam_next_block, View.GONE)
            views.removeAllViews(R.id.exam_list_container)
            views.setViewVisibility(R.id.exam_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.exam_empty,
                context.getString(R.string.widget_exam_none),
            )
            manager.updateAppWidget(appWidgetId, views)
            return
        }

        views.setViewVisibility(R.id.exam_empty, View.GONE)

        // 最近一场：大字卡片。
        val next = exam.items.first()
        views.setViewVisibility(R.id.exam_next_block, View.VISIBLE)
        views.setTextViewText(R.id.exam_next_name, next.name)
        views.setTextViewText(R.id.exam_next_days, next.daysLeftText)
        val meta = buildString {
            if (next.startText.isNotEmpty()) append(next.startText)
            if (next.location.isNotEmpty()) {
                if (isNotEmpty()) append(" · ")
                append(next.location)
            }
        }
        views.setTextViewText(R.id.exam_next_meta, meta)

        // 其余考试：小行列表（窄卡只带 1 行，宽卡最多 3 行）。
        views.removeAllViews(R.id.exam_list_container)
        val limit = if (widgetWidthDp(manager, appWidgetId) >= WIDE_CARD_DP) {
            minOf(3, exam.items.size - 1)
        } else {
            minOf(1, exam.items.size - 1)
        }
        for (item in exam.items.drop(1).take(limit)) {
            val row = RemoteViews(context.packageName, R.layout.widget_exam_row)
            row.setTextViewText(R.id.exam_row_name, item.name)
            row.setTextViewText(R.id.exam_row_meta, item.startText)
            row.setTextViewText(R.id.exam_row_days, item.daysLeftText)
            views.addView(R.id.exam_list_container, row)
        }
        manager.updateAppWidget(appWidgetId, views)
    }
}
