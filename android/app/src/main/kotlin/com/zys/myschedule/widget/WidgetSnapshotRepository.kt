package com.zys.myschedule.widget

import android.content.Context
import android.content.Intent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import java.io.File

/**
 * 快照落盘：`context.filesDir/widget/schedule_snapshot.json`。
 *
 * Hive 的 `.hive` 是 Dart 私有格式，Kotlin 读不了，所以由 Dart 经
 * MethodChannel 把 JSON 字符串发过来，本类负责**原子写**落盘
 *（先写 `.tmp` 再 rename，防半截文件被小组件进程读到）。
 *
 * 目录不需要任何权限：`filesDir` 是应用私有目录。
 */
class WidgetSnapshotRepository(private val context: Context) {

    private val dir: File get() = File(context.filesDir, DIR_NAME)
    private val snapshotFile: File get() = File(dir, FILE_NAME)

    /** 原子写入快照。失败抛异常给调用方（MainActivity 会转成 MethodChannel error）。 */
    fun write(json: String) {
        val dirFile = dir
        if (!dirFile.exists()) dirFile.mkdirs()
        val tmp = File(dirFile, "$FILE_NAME.tmp")
        tmp.writeText(json)
        if (!tmp.renameTo(snapshotFile)) {
            // rename 失败（极端：目标文件被占用）→ 直接覆盖写，再清临时文件。
            snapshotFile.writeText(json)
            tmp.delete()
        }
    }

    /** 读并解析快照；文件缺失 / 损坏 / 版本不匹配都返回 `null`（调用方走空态）。 */
    fun read(): WidgetSnapshot? {
        return try {
            if (!snapshotFile.exists()) return null
            WidgetSnapshotParser.parse(snapshotFile.readText())
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val DIR_NAME = "widget"
        const val FILE_NAME = "schedule_snapshot.json"
    }
}

/**
 * 小组件刷新：按类型分组触发 provider 的 onUpdate。
 *
 * 走广播而不是 `AppWidgetManager.updateAppWidget(...)`：渲染逻辑集中在
 * provider 一处，广播只负责"通知该重画了"，避免两套渲染入口。
 */
object WidgetUpdater {

    private val PROVIDERS = listOf(
        TodayWidgetProvider::class.java,
        WeekWidgetProvider::class.java,
        HomeworkWidgetProvider::class.java,
        ExamWidgetProvider::class.java,
    )

    fun refreshAll(context: Context) {
        for (provider in PROVIDERS) refreshType(context, provider)
    }

    private fun refreshType(context: Context, provider: Class<*>) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, provider))
        if (ids.isEmpty()) return
        val intent = Intent(context, provider).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(intent)
    }
}
