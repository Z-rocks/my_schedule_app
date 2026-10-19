package com.zys.myschedule.reminder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONObject

/**
 * 排期落地：把 Dart 算好的提醒写进 AlarmManager。
 *
 * ## 为什么用 AlarmManager 而不是 WorkManager
 *
 * WorkManager 只保证"大致时间"（可延迟、Doze 下会合并），而作业提醒要的是
 * **卡点**（截止前 10 分钟就是 10 分钟）。AlarmManager 的
 * `setExactAndAllowWhileIdle` 才能在息屏 + Doze 下准时叫醒。
 *
 * ## 权限降级
 *
 * Android 12+ 的精确闹钟需要 `SCHEDULE_EXACT_ALARM`（manifest 里已声明
 * `USE_EXACT_ALARM`，本 App 属"提醒类"用途，安装即授予）。
 * 若用户在系统里手动关掉，则退化为 `setAndAllowWhileIdle`（可能晚几分钟），
 * 功能不因此失效——晚到总比不到好。
 */
object HomeworkReminderScheduler {

    private const val TAG = "HomeworkReminder"

    private fun prefs(context: Context) =
        context.getSharedPreferences(ReminderContract.PREFS, Context.MODE_PRIVATE)

    /**
     * 全量替换排期：取消"新排期里没有的旧闹钟"，再排新的。
     *
     * **不能"先全取消再全重排"**：App 回前台会重排，如果恰好卡在某条提醒
     * 触发前 1 秒，先取消就会漏掉这条（新排期里它已算"过去"不会再排）。
     * 所以这里按 requestCode 做增量 diff，并且**只取消明显还在未来的**
     * 陈旧闹钟（60s 之内的留给它照常响——最多重复一次，不会漏）。
     */
    fun sync(context: Context, planJson: String): Boolean {
        val prefs = prefs(context)
        val oldPlanJson = prefs.getString(ReminderContract.PREF_PLAN_JSON, null)
        val newItems = parseItems(planJson)
        val newCodes = newItems.map { it.requestCode }.toSet()
        val retained = cancelStale(context, oldPlanJson, newCodes)
        prefs.edit().putString(ReminderContract.PREF_PLAN_JSON, planJson).apply()
        val scheduled = scheduleItems(context, newItems, retained)
        Log.i(TAG, "排期已更新：${newItems.size} 条候选，排上 $scheduled 个闹钟")
        return true
    }

    /** 按已存盘的排期重排（开机 / 应用更新后系统会清空闹钟）。 */
    fun reschedule(context: Context) {
        val planJson = prefs(context).getString(ReminderContract.PREF_PLAN_JSON, null) ?: return
        val items = parseItems(planJson)
        val scheduled = scheduleItems(context, items, emptySet())
        Log.i(TAG, "开机重排：$scheduled 个闹钟")
    }

    /** 取消全部提醒（关闭开关时调用）。 */
    fun cancelAll(context: Context) {
        val p = prefs(context)
        val codes = p.getStringSet(ReminderContract.PREF_SCHEDULED_CODES, emptySet()) ?: emptySet()
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (code in codes) {
            val pi = pendingIntent(context, code.toInt(), null, create = false)
            if (pi != null) {
                am.cancel(pi)
                pi.cancel()
            }
        }
        p.edit().remove(ReminderContract.PREF_SCHEDULED_CODES).apply()
        if (codes.isNotEmpty()) Log.i(TAG, "已取消 ${codes.size} 个闹钟")
    }

    /**
     * 取消旧排期里"新排期不再需要、且触发时刻还在 60s 之外"的闹钟。
     *
     * @return 保留的（即将触发的）requestCode，排新闹钟时要把它们算进去，
     *         否则它们会从记录里丢失、无法再被取消。
     */
    private fun cancelStale(
        context: Context,
        oldPlanJson: String?,
        newCodes: Set<Int>,
    ): Set<Int> {
        val p = prefs(context)
        val recorded = p.getStringSet(ReminderContract.PREF_SCHEDULED_CODES, emptySet())
            ?: emptySet()
        if (recorded.isEmpty()) return emptySet()

        // 旧排期里能查到 fireAt 的，按"是否即将触发"决定留还是取消。
        val oldFireAt: Map<Int, Long> = parseItems(oldPlanJson ?: "")
            .associate { it.requestCode to it.fireAtMillis }
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        val retained = mutableSetOf<Int>()

        for (codeText in recorded) {
            val code = codeText.toIntOrNull() ?: continue
            if (code in newCodes) continue // 新排期还要它，稍后覆盖排即可
            val fireAt = oldFireAt[code]
            if (fireAt != null && fireAt - now <= 60_000L && fireAt > now) {
                // 马上要响的：留着，别因为重排把用户刚要收到的提醒弄丢。
                retained.add(code)
                continue
            }
            val pi = pendingIntent(context, code, null, create = false)
            if (pi != null) {
                am.cancel(pi)
                pi.cancel()
            }
        }
        return retained
    }

    /** 逐条排闹钟，返回成功排上的个数。 */
    private fun scheduleItems(
        context: Context,
        items: List<ReminderItem>,
        retained: Set<Int>,
    ): Int {
        val now = System.currentTimeMillis()
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val codes = retained.map { it.toString() }.toMutableSet()
        var count = 0

        for (item in items) {
            // 已过点的（含 2s 内即将过点）不排：避免"刚排好就立刻响"。
            if (item.fireAtMillis <= now + 2_000L) continue
            val pi = pendingIntent(context, item.requestCode, item.rawJson, create = true) ?: continue
            try {
                if (canScheduleExact(am)) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.fireAtMillis, pi)
                } else {
                    // 降级：可能晚几分钟，但不丢提醒。
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.fireAtMillis, pi)
                }
                codes.add(item.requestCode.toString())
                count++
            } catch (e: SecurityException) {
                Log.w(TAG, "排闹钟被拒（缺精确闹钟权限？）", e)
                try {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.fireAtMillis, pi)
                    codes.add(item.requestCode.toString())
                    count++
                } catch (inner: Exception) {
                    Log.w(TAG, "降级排闹钟也失败", inner)
                }
            } catch (e: Exception) {
                Log.w(TAG, "排闹钟失败：${item.homeworkId}", e)
            }
        }

        prefs(context).edit()
            .putStringSet(ReminderContract.PREF_SCHEDULED_CODES, codes)
            .apply()
        return count
    }

    /** 解析排期 JSON 里的 items；坏数据返回空列表。 */
    private fun parseItems(planJson: String): List<ReminderItem> {
        if (planJson.isBlank()) return emptyList()
        return try {
            val root = JSONObject(planJson)
            val version = root.optInt("version", 0)
            if (version != ReminderContract.PLAN_VERSION) {
                Log.w(TAG, "排期版本 $version 与本地 ${ReminderContract.PLAN_VERSION} 不一致，忽略")
                return emptyList()
            }
            val array = root.optJSONArray("items") ?: return emptyList()
            (0 until array.length()).mapNotNull { i ->
                array.optJSONObject(i)?.toString()?.let { ReminderItem.fromJson(it) }
            }
        } catch (e: Exception) {
            Log.w(TAG, "排期 JSON 解析失败", e)
            emptyList()
        }
    }

    /** 是否可以用精确闹钟（Android 12 以下恒为 true）。 */
    fun canScheduleExact(am: AlarmManager): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.canScheduleExactAlarms()
        } else {
            true
        }
    }

    /**
     * 取（或创建）某条排期的 PendingIntent。
     *
     * [itemJson] 为 null 时只用于查找（取消路径），不创建。
     * action 固定 + requestCode 唯一 = 同一档位始终指向同一个 PendingIntent，
     * 重复排期只会覆盖、不会重复响。
     */
    private fun pendingIntent(
        context: Context,
        requestCode: Int,
        itemJson: String?,
        create: Boolean,
    ): PendingIntent? {
        val intent = Intent(context, HomeworkReminderReceiver::class.java).apply {
            action = ReminderContract.ACTION_FIRE
            if (itemJson != null) putExtra(ReminderContract.EXTRA_ITEM, itemJson)
        }
        val flags = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE else 0) or
            if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }
}
