package com.zys.myschedule.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import com.zys.myschedule.MainActivity
import com.zys.myschedule.R

/**
 * 小组件 provider 基类。
 *
 * - [onUpdate] 统一入口：读快照（版本不匹配/损坏 → null）→ [render]。
 * - [onAppWidgetOptionsChanged]：用户缩放卡片后也要重画（多档尺寸的
 *   显示条数依赖 options），这里直接转给 [onUpdate]。
 * - 每张卡一个 [render]，拿到"可能为 null 的快照"，自行决定空态样式。
 */
abstract class BaseWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: android.appwidget.AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val snapshot = WidgetSnapshotRepository(context).read()
        for (id in appWidgetIds) {
            render(context, manager, id, snapshot)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: android.appwidget.AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        onUpdate(context, manager, intArrayOf(appWidgetId))
    }

    /** 渲染一张卡片。[snapshot] 为 null 时渲染空态（快照缺失/损坏/版本旧）。 */
    protected abstract fun render(
        context: Context,
        manager: android.appwidget.AppWidgetManager,
        appWidgetId: Int,
        snapshot: WidgetSnapshot?,
    )
}

/**
 * 点击卡片拉起 MainActivity 并带上目标页。
 *
 * `FLAG_IMMUTABLE`（minSdk 24 可无条件使用）；`FLAG_UPDATE_CURRENT` +
 * 每个目标独立 requestCode，保证 onNewIntent 拿到最新 extra。
 */
internal fun widgetLaunchIntent(context: Context, target: String): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        action = Intent.ACTION_MAIN
        addCategory(Intent.CATEGORY_LAUNCHER)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK
        putExtra(WidgetSnapshotContract.EXTRA_TARGET, target)
    }
    return PendingIntent.getActivity(
        context,
        target.hashCode(),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/** 当前卡片宽度（dp）：取自 widget options，用于多档尺寸自适应（小卡少显几行）。 */
internal fun widgetWidthDp(
    manager: android.appwidget.AppWidgetManager,
    appWidgetId: Int,
): Int {
    val options = manager.getAppWidgetOptions(appWidgetId)
    val width = options.getInt(android.appwidget.AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
    return if (width <= 0) DEFAULT_WIDTH_DP else width
}

/**
 * 右上角"更新于 hh:mm"：**只在宽卡（≥[WIDE_CARD_DP]）显示**。
 *
 * 真机踩到过：2×2 窄卡（约 150dp）里它和标题挤同一行，标题被压成
 * "周六 · 第…"，日期周次这种关键信息反而看不全。信息优先级：
 * 标题（日期/周次、计数）> 更新时间戳，所以窄卡直接隐藏它。
 */
internal fun applyUpdatedLabel(
    views: android.widget.RemoteViews,
    manager: android.appwidget.AppWidgetManager,
    appWidgetId: Int,
    label: String,
) {
    if (widgetWidthDp(manager, appWidgetId) >= WIDE_CARD_DP) {
        views.setTextViewText(R.id.updated_text, label)
        views.setViewVisibility(R.id.updated_text, android.view.View.VISIBLE)
    } else {
        views.setViewVisibility(R.id.updated_text, android.view.View.GONE)
    }
}

/** 宽卡门槛：宽度 dp ≥ 此值视为 4×2 及以上的宽卡。 */
internal const val WIDE_CARD_DP = 250

/** 拿不到 options 时的兜底宽度：按 2×2 卡处理（保守，少显内容）。 */
private const val DEFAULT_WIDTH_DP = 150

/**
 * 是否平板（sw ≥ 600dp）：今天课表卡在平板上多显几行、
 * 字号由 values-sw600dp/widget_dimens.xml 一并放大。
 */
internal fun isTablet(context: Context): Boolean =
    context.resources.configuration.smallestScreenWidthDp >= 600
