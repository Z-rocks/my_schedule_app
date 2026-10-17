package com.zys.myschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.zys.myschedule.R

/**
 * 「下一节课」卡片（2×2 / 2×4，平板按 dimens 放大）。
 *
 * v2 改造（2026-10-17）：原来是"今天全部课程"的缩略列表，2×2 里最多塞 4 行，
 * 课程一多就显示不全，用户真正想一眼看到的却是"现在/接下来上什么"。
 * 现在只渲染**一节**：课程名 + 节次时间 + 地点，右上角给状态
 * （`进行中` / `10:25 上课`）。今天完整的课程列表由 [WeekWidgetProvider] 承担。
 *
 * 判定逻辑全在 Dart 侧（`WidgetSnapshotService._nextSessionJson`）：
 * 小组件只按 `nextSession.state` 选文案颜色，不解析时间。
 *
 * 本卡**不显示**"更新于 hh:mm"：2×2 宽度放不下，而状态标签（"进行中"/
 * "10:25 上课"）对用户的时效价值更高。
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

        val schedule = snapshot.schedule
        val next = schedule.nextSession
        // courseIdx 越界（旧快照 / 数据错位）时按"没有下一节"处理，绝不索引越界。
        val course = next?.let { schedule.courseTable.getOrNull(it.courseIdx) }

        when {
            !snapshot.hasSemester -> {
                showEmptyState(context, views, R.string.widget_empty_no_semester)
            }

            next == null || course == null -> {
                // 四个空态分层：没配学期 / 没同步到课 / 本周没课 / 今天没课。
                val textRes = when {
                    snapshot.scheduleEmpty -> R.string.widget_empty_no_courses
                    !snapshot.weekHasClass -> R.string.widget_empty_no_class_this_week
                    else -> R.string.widget_empty_no_class_today
                }
                showEmptyState(context, views, textRes)
            }

            next.state == STATE_FINISHED -> {
                // 今天上完了：不拿最后一门课冒充"下一节"，直接说清楚。
                showEmptyState(context, views, R.string.widget_empty_all_done)
            }

            else -> {
                views.setViewVisibility(R.id.empty_text, View.GONE)
                views.setViewVisibility(R.id.next_block, View.VISIBLE)
                views.setTextViewText(R.id.next_name, course.name)
                views.setInt(R.id.next_color_bar, "setBackgroundColor", course.color)
                views.setTextViewText(R.id.next_section, next.sectionText)

                if (course.room.isNotEmpty()) {
                    views.setViewVisibility(R.id.next_room, View.VISIBLE)
                    views.setTextViewText(R.id.next_room, course.room)
                } else {
                    views.setViewVisibility(R.id.next_room, View.GONE)
                }

                // 只在"正在上课"时显示状态位：2×2 卡（约 126dp 可用宽）里
                // "周六 · 第8周" 已经吃掉 ~80dp，再挤一个 "10:25 上课" 会把标题
                // 压成"周六 · 第…"（老版本真机踩过）。而 upcoming 的开课时间
                // next_section 里本来就有（"3-4节 10:25-11:10"），状态位是冗余的。
                if (next.state == STATE_ONGOING && next.label.isNotEmpty()) {
                    views.setViewVisibility(R.id.next_state, View.VISIBLE)
                    views.setTextViewText(R.id.next_state, next.label)
                    views.setTextColor(R.id.next_state, context.getColor(R.color.widget_accent))
                } else {
                    views.setViewVisibility(R.id.next_state, View.GONE)
                }
            }
        }

        manager.updateAppWidget(appWidgetId, views)
    }

    private fun showEmptyState(context: Context, views: RemoteViews, textRes: Int) {
        views.setViewVisibility(R.id.next_block, View.GONE)
        views.setViewVisibility(R.id.next_state, View.GONE)
        views.setViewVisibility(R.id.empty_text, View.VISIBLE)
        views.setTextViewText(R.id.empty_text, context.getString(textRes))
    }

    private companion object {
        /**
         * 与 Dart `_nextSessionJson` 的 state 取值保持一致：
         * `ongoing`（正在上）/ `upcoming`（接下来）/ `finished`（今天上完）/ `unknown`（无作息）。
         * 只有 `ongoing` 会在卡面上显示状态位，`finished` 走空态，其余不显示。
         */
        const val STATE_ONGOING = "ongoing"
        const val STATE_FINISHED = "finished"
    }
}
