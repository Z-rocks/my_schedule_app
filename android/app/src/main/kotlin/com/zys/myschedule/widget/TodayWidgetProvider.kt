package com.zys.myschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.zys.myschedule.R

/**
 * 今天课表（2×2 / 2×4，横向拉伸后平板也适用）。
 *
 * 内容：日期标题（周五 · 第 8 周）、当天课程序列（跨节合并成一段，
 * 带左侧课程色条）、角落"更新于 hh:mm"；今天没课 / 快照缺失各有空态。
 * 点击整卡 → 打开课表页。
 */
class TodayWidgetProvider : BaseWidgetProvider() {

    override fun render(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        snapshot: WidgetSnapshot?,
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
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
            R.id.today_title,
            context.getString(
                R.string.widget_today_title,
                snapshot.todayLabel,
                snapshot.week,
            ),
        )
        // 窄卡（2×2，约 150dp）放不下"周六 · 第 8 周" + "更新于 12:58"：
        // 真机上标题被挤成"周六 · 第…"。窄卡隐藏时间戳，见 applyUpdatedLabel。
        applyUpdatedLabel(views, manager, appWidgetId, snapshot.updatedLabel)

        val sessions = snapshot.schedule.todaySessions
            .filter { it.courseIdx in snapshot.schedule.courseTable.indices }
        if (!snapshot.hasSemester) {
            showEmptyState(context, views, R.string.widget_empty_no_semester)
        } else if (sessions.isEmpty()) {
            // 三个层级分清楚：没配学期 / 根本没同步到课 / 本周没课 / 今天没课。
            val textRes = when {
                snapshot.scheduleEmpty -> R.string.widget_empty_no_courses
                !snapshot.weekHasClass -> R.string.widget_empty_no_class_this_week
                else -> R.string.widget_empty_no_class_today
            }
            showEmptyState(context, views, textRes)
        } else {
            views.setViewVisibility(R.id.empty_text, View.GONE)
            val container = R.id.sessions_container
            views.removeAllViews(container)
            // 行数上限：卡面高度有限，全塞会溢出。窄卡 4 行、宽卡 6 行、
            // 平板（sw600dp+，dimens 已放大）8 行；截断时补一行"等 N 节课"。
            val limit = when {
                isTablet(context) -> TABLET_MAX_SESSIONS
                widgetWidthDp(manager, appWidgetId) >= WIDE_CARD_DP ->
                    WIDE_MAX_SESSIONS
                else -> NARROW_MAX_SESSIONS
            }
            val shown = if (sessions.size > limit) {
                if (limit > 1) sessions.take(limit - 1) else sessions.take(1)
            } else {
                sessions
            }
            for (session in shown) {
                val course = snapshot.schedule.courseTable[session.courseIdx]
                val row = RemoteViews(context.packageName, R.layout.widget_today_row)
                row.setTextViewText(R.id.course_name, course.name)
                row.setTextViewText(R.id.section_text, session.sectionText)
                if (course.room.isNotEmpty()) {
                    row.setTextViewText(R.id.room_text, course.room)
                } else {
                    row.setViewVisibility(R.id.room_text, View.GONE)
                }
                row.setInt(R.id.color_bar, "setBackgroundColor", course.color)
                views.addView(container, row)
            }
            if (shown.size < sessions.size) {
                val more = RemoteViews(context.packageName, R.layout.widget_today_row)
                more.setTextViewText(R.id.course_name, "等 ${sessions.size} 节课")
                more.setViewVisibility(R.id.room_text, View.GONE)
                more.setViewVisibility(R.id.section_text, View.GONE)
                more.setInt(R.id.color_bar, "setBackgroundColor", 0)
                views.addView(container, more)
            }
        }

        manager.updateAppWidget(appWidgetId, views)
    }

    private fun showEmptyState(context: Context, views: RemoteViews, textRes: Int) {
        views.removeAllViews(R.id.sessions_container)
        views.setViewVisibility(R.id.empty_text, View.VISIBLE)
        views.setTextViewText(R.id.empty_text, context.getString(textRes))
    }

    private companion object {
        const val NARROW_MAX_SESSIONS = 4
        const val WIDE_MAX_SESSIONS = 6
        const val TABLET_MAX_SESSIONS = 8
    }
}
