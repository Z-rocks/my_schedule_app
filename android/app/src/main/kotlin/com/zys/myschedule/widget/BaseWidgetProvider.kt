package com.zys.myschedule.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
import com.zys.myschedule.MainActivity
import com.zys.myschedule.R

/**
 * 小组件 provider 基类。
 *
 * - [onUpdate] 统一入口：读快照（版本不匹配/损坏 → null）→ [render]。
 * - [onAppWidgetOptionsChanged]：用户缩放卡片后也要重画（多档尺寸的
 *   显示条数依赖 options），这里直接转给 [onUpdate]。
 * - 每张卡一个 [render]，拿到"可能为 null 的快照"，自行决定空态样式。
 *
 * **渲染异常兜底**：任何 provider 的 [render] 抛异常，系统会直接把整张卡
 * 换成黑色占位 + "载入窗口小部件时出现问题"——用户既看不到内容，也不知道
 * 该做什么。所以这里统一 catch：记录完整堆栈（logcat tag `WidgetRender`），
 * 再用最简布局显示"点一下打开 App"。宁可少显示内容，也不要一张黑卡。
 */
abstract class BaseWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: android.appwidget.AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val snapshot = try {
            WidgetSnapshotRepository(context).read()
        } catch (t: Throwable) {
            // read() 内部已兜底，这里再包一层：宁可空态，也不要整卡崩。
            Log.e(TAG, "读取快照失败", t)
            null
        }
        for (id in appWidgetIds) {
            try {
                render(context, manager, id, snapshot)
            } catch (t: Throwable) {
                Log.e(
                    TAG,
                    "渲染失败 provider=${javaClass.simpleName} appWidgetId=$id " +
                        "snapshotNull=${snapshot == null}",
                    t,
                )
                renderErrorFallback(context, manager, id)
            }
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

    /** 渲染兜底卡（[render] 抛异常时）。本身也必须绝不抛异常。 */
    private fun renderErrorFallback(
        context: Context,
        manager: android.appwidget.AppWidgetManager,
        appWidgetId: Int,
    ) {
        try {
            val views = RemoteViews(context.packageName, R.layout.widget_error)
            views.setTextViewText(
                R.id.error_text,
                context.getString(R.string.widget_render_error),
            )
            views.setOnClickPendingIntent(
                android.R.id.background,
                widgetLaunchIntent(context, WidgetSnapshotContract.TARGET_HOME),
            )
            manager.updateAppWidget(appWidgetId, views)
        } catch (t: Throwable) {
            // 连兜底都失败：只能记日志，让系统显示它自己的占位。
            Log.e(TAG, "兜底渲染也失败 appWidgetId=$appWidgetId", t)
        }
    }

    private companion object {
        const val TAG = "WidgetRender"
    }
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
 * 当前卡片高度（dp）。
 *
 * 取 `OPTION_APPWIDGET_MIN_HEIGHT`（下界）而不是 MAX_HEIGHT：**少估比多估安全**
 * ——算少了只是少显示一行，算多了会把最后一行顶出卡面被裁掉，看起来像 bug。
 */
internal fun widgetHeightDp(
    manager: android.appwidget.AppWidgetManager,
    appWidgetId: Int,
): Int {
    val options = manager.getAppWidgetOptions(appWidgetId)
    val height =
        options.getInt(android.appwidget.AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
    return if (height <= 0) DEFAULT_HEIGHT_DP else height
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

/** 拿不到 options 时的兜底高度：按 2×2 卡处理（保守，少显内容）。 */
private const val DEFAULT_HEIGHT_DP = 140
