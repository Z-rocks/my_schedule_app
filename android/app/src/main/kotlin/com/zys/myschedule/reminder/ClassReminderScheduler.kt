package com.zys.myschedule.reminder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONObject

/**
 * 上课提醒排期落地。
 *
 * 与 [HomeworkReminderScheduler] 的结构相似（同样用 AlarmManager + 增量 diff），
 * 但**刻意不复用**：作业提醒要起前台服务做后台校验、排期条目带着
 * `homeworkId` / `deadlineMillis` 这些作业专属字段，硬合并会让两边的
 * 字段含义互相污染。这里只做"到点发通知"这一件事，代码短得多。
 *
 * 排期只覆盖未来 7 天（Dart 侧 `kClassReminderHorizonDays`），
 * 因此闹钟数量稳定在几十个以内，不会撞上 ROM 的闹钟数上限。
 */
object ClassReminderScheduler {

    private const val TAG = "ClassReminder"

    private fun prefs(context: Context) =
        context.getSharedPreferences(ClassReminderContract.PREFS, Context.MODE_PRIVATE)

    /** 全量替换排期。返回是否成功。 */
    fun sync(context: Context, planJson: String): Boolean {
        val p = prefs(context)
        val oldPlanJson = p.getString(ClassReminderContract.PREF_PLAN_JSON, null)
        val newItems = parseItems(planJson)
        val newCodes = newItems.map { it.requestCode }.toSet()

        cancelStale(context, oldPlanJson, newCodes)
        p.edit().putString(ClassReminderContract.PREF_PLAN_JSON, planJson).apply()

        val count = scheduleItems(context, newItems)
        Log.i(TAG, "排期已更新：${newItems.size} 条候选，排上 $count 个闹钟")
        return true
    }

    /** 开机 / 应用更新后按已存盘的排期重排（系统的闹钟不持久化）。 */
    fun reschedule(context: Context) {
        val planJson =
            prefs(context).getString(ClassReminderContract.PREF_PLAN_JSON, null) ?: return
        val items = parseItems(planJson)
        val count = scheduleItems(context, items)
        Log.i(TAG, "开机重排：$count 个闹钟")
    }

    /** 取消全部（关闭开关时调用）。 */
    fun cancelAll(context: Context) {
        val p = prefs(context)
        val codes = p.getStringSet(ClassReminderContract.PREF_SCHEDULED_CODES, emptySet())
            ?: emptySet()
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (code in codes) {
            val pi = pendingIntent(context, code.toIntOrNull() ?: continue, null, create = false)
            if (pi != null) {
                am.cancel(pi)
                pi.cancel()
            }
        }
        p.edit()
            .remove(ClassReminderContract.PREF_SCHEDULED_CODES)
            .remove(ClassReminderContract.PREF_PLAN_JSON)
            .apply()
        if (codes.isNotEmpty()) Log.i(TAG, "已取消 ${codes.size} 个闹钟")
    }

    /**
     * 取消旧排期里"新排期不再需要、且不在 60 秒内"的闹钟。
     *
     * 60 秒保护：App 回前台会重排，若恰好卡在某条提醒触发前 1 秒，
     * 先取消就会漏掉这条（新排期里它已算"过去"，不会再排）。
     * 宁可重复响一次，也不能漏。
     */
    private fun cancelStale(
        context: Context,
        oldPlanJson: String?,
        newCodes: Set<Int>,
    ) {
        val p = prefs(context)
        val recorded = p.getStringSet(ClassReminderContract.PREF_SCHEDULED_CODES, emptySet())
            ?: emptySet()
        if (recorded.isEmpty()) return

        val oldFireAt: Map<Int, Long> =
            parseItems(oldPlanJson ?: "").associate { it.requestCode to it.fireAtMillis }
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        val retained = mutableSetOf<String>()

        for (codeText in recorded) {
            val code = codeText.toIntOrNull() ?: continue
            if (code in newCodes) {
                retained.add(codeText) // 新排期还要它，稍后覆盖排即可
                continue
            }
            val fireAt = oldFireAt[code]
            if (fireAt != null && fireAt > now && fireAt - now <= 60_000L) {
                retained.add(codeText) // 马上要响的，留着
                continue
            }
            val pi = pendingIntent(context, code, null, create = false)
            if (pi != null) {
                am.cancel(pi)
                pi.cancel()
            }
        }
        p.edit().putStringSet(ClassReminderContract.PREF_SCHEDULED_CODES, retained).apply()
    }

    /** 逐条排闹钟，返回成功排上的个数。 */
    private fun scheduleItems(context: Context, items: List<ClassItem>): Int {
        val now = System.currentTimeMillis()
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val codes = (prefs(context)
            .getStringSet(ClassReminderContract.PREF_SCHEDULED_CODES, emptySet())
            ?: emptySet()).toMutableSet()
        var count = 0

        for (item in items) {
            // 已过点的（含 2s 内即将过点）不排：避免"刚排好就立刻响"。
            if (item.fireAtMillis <= now + 2_000L) continue
            val pi = pendingIntent(context, item.requestCode, item.rawJson, create = true)
                ?: continue
            try {
                if (HomeworkReminderScheduler.canScheduleExact(am)) {
                    am.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        item.fireAtMillis,
                        pi,
                    )
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
                Log.w(TAG, "排闹钟失败：${item.requestCode}", e)
            }
        }

        prefs(context).edit()
            .putStringSet(ClassReminderContract.PREF_SCHEDULED_CODES, codes)
            .apply()
        return count
    }

    private fun parseItems(planJson: String): List<ClassItem> {
        if (planJson.isBlank()) return emptyList()
        return try {
            val root = JSONObject(planJson)
            val version = root.optInt("version", 0)
            if (version != ClassReminderContract.PLAN_VERSION) {
                Log.w(TAG, "排期版本 $version 与本地不一致，忽略")
                return emptyList()
            }
            val array = root.optJSONArray("items") ?: return emptyList()
            (0 until array.length()).mapNotNull { i ->
                val obj = array.optJSONObject(i) ?: return@mapNotNull null
                val code = obj.optInt("requestCode", 0)
                val fireAt = obj.optLong("fireAtMillis", 0L)
                val title = obj.optString("title")
                val body = obj.optString("body")
                if (code == 0 || fireAt <= 0L || title.isEmpty()) {
                    return@mapNotNull null
                }
                ClassItem(code, fireAt, title, body, obj.toString())
            }
        } catch (e: Exception) {
            Log.w(TAG, "排期 JSON 解析失败", e)
            emptyList()
        }
    }

    /**
     * 取（或创建）某条排期的 PendingIntent。
     *
     * action 固定 + requestCode 唯一 = 同一档位始终指向同一个 PendingIntent，
     * 重复排期只会覆盖、不会重复响。
     */
    private fun pendingIntent(
        context: Context,
        requestCode: Int,
        itemJson: String?,
        create: Boolean,
    ): PendingIntent? {
        val intent = Intent(context, ClassReminderReceiver::class.java).apply {
            action = ClassReminderContract.ACTION_FIRE
            if (itemJson != null) putExtra(ClassReminderContract.EXTRA_ITEM, itemJson)
        }
        val flags = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE else 0) or
            if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    /** 排期条目的最小结构。 */
    private data class ClassItem(
        val requestCode: Int,
        val fireAtMillis: Long,
        val title: String,
        val body: String,
        val rawJson: String,
    )
}
