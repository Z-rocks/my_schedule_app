package com.zys.myschedule.reminder

import org.json.JSONObject

/**
 * 一条提醒排期（Kotlin 侧镜像）。
 *
 * 由 Dart `HomeworkReminderItem.toJson()` 产出，字段含义见 Dart 侧同名类。
 * **原样保存 [rawJson]**：广播里传的就是它，校验服务再把整条转给 Dart，
 * 这样新增字段不必改这里（Dart 自己认识自己的 JSON）。
 */
data class ReminderItem(
    val homeworkId: String,
    val pluginId: String,
    val title: String,
    val courseName: String,
    val deadlineMillis: Long,
    val fireAtMillis: Long,
    val offsetMinutes: Int,
    val slot: Int,
    val totalSlots: Int,
    val courseId: String,
    val courseRefJson: String?,
    val notifyWhenCheckFails: Boolean,
    val rawJson: String,
) {
    /** 通知标题：课程名优先（与 Dart 侧文案保持一致）。 */
    val notificationTitle: String
        get() = if (courseName.isBlank()) "作业快截止了" else "作业提醒 · $courseName"

    /** 通知正文：`「标题」还有 X 分钟截止`。 */
    val notificationBody: String
        get() {
            val remain = when {
                offsetMinutes >= 1440 && offsetMinutes % 1440 == 0 ->
                    "${offsetMinutes / 1440} 天"
                offsetMinutes >= 60 && offsetMinutes % 60 == 0 ->
                    "${offsetMinutes / 60} 小时"
                else -> "$offsetMinutes 分钟"
            }
            val slotText =
                if (totalSlots > 1) "（共 $totalSlots 次提醒的第 $slot 次）" else ""
            return "「$title」还有 $remain 截止$slotText"
        }

    /** 稳定通知 id：同一份作业的同一档始终覆盖同一条通知。 */
    val notificationId: Int
        get() = ReminderContract.NOTIFICATION_ID_BASE +
            (("$homeworkId#$offsetMinutes").hashCode() and 0xFFFFF)

    /** 稳定闹钟 requestCode（取消时靠它找回同一个 PendingIntent）。 */
    val requestCode: Int
        get() = ("$homeworkId#$offsetMinutes").hashCode() and 0x7FFFFFFF

    companion object {
        /** 解析一条排期；关键字段缺失返回 null（该条被跳过，不影响其他）。 */
        fun fromJson(raw: String): ReminderItem? {
            return try {
                val json = JSONObject(raw)
                val homeworkId = json.optString("homeworkId")
                val fireAt = json.optLong("fireAtMillis", 0L)
                if (homeworkId.isEmpty() || fireAt <= 0L) {
                    null
                } else {
                    ReminderItem(
                        homeworkId = homeworkId,
                        pluginId = json.optString("pluginId"),
                        title = json.optString("title"),
                        courseName = json.optString("courseName"),
                        deadlineMillis = json.optLong("deadlineMillis", 0L),
                        fireAtMillis = fireAt,
                        offsetMinutes = json.optInt("offsetMinutes", 0),
                        slot = json.optInt("slot", 1),
                        totalSlots = json.optInt("totalSlots", 1),
                        courseId = json.optString("courseId"),
                        // courseRef 可能是 null / 对象；原样转成字符串交给 Dart
                        courseRefJson = json.optJSONObject("courseRef")?.toString(),
                        notifyWhenCheckFails = json.optBoolean("notifyWhenCheckFails", true),
                        rawJson = raw,
                    )
                }
            } catch (e: Exception) {
                null
            }
        }
    }
}
