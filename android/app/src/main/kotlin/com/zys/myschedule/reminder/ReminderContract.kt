package com.zys.myschedule.reminder

/**
 * 作业提醒的 schema / 通道契约。
 *
 * **唯一事实来源在 Dart 侧**（`homework_reminder_plan.dart` 的
 * `kHomeworkReminderPlanVersion` 与各 JSON 键名）；这里只是同值副本。
 * 字段含义变化时两边必须同改，否则按"排期版本不匹配 → 忽略该条"处理
 * （不会崩，只是不提醒）。
 */
object ReminderContract {
    /** Dart → Kotlin 通道（Dart 侧 `ReminderBridge` 必须一致）。 */
    const val CHANNEL = "com.zys.myschedule/reminder"

    /** 后台校验通道（Dart 侧 `kHomeworkCheckChannelName` 必须一致）。 */
    const val CHANNEL_CHECK = "com.zys.myschedule/reminder_check"

    /** 排期 schema 版本（Dart `kHomeworkReminderPlanVersion`）。 */
    const val PLAN_VERSION = 1

    /** 本功能专用的 SharedPreferences。 */
    const val PREFS = "homework_reminder"

    /** 最近一次下发的排期 JSON（重启 / 开机后据此重排闹钟）。 */
    const val PREF_PLAN_JSON = "plan_json"

    /** 后台校验入口的 Dart 回调句柄（long，0 表示未登记）。 */
    const val PREF_CHECK_HANDLE = "check_handle"

    /** 已排的闹钟 requestCode 列表（StringSet，用于精确取消）。 */
    const val PREF_SCHEDULED_CODES = "scheduled_codes"

    /** 闹钟触发广播 action。 */
    const val ACTION_FIRE = "com.zys.myschedule.action.HOMEWORK_REMINDER_FIRE"

    /** 广播 / 服务 intent 里携带的单条排期 JSON。 */
    const val EXTRA_ITEM = "reminder_item"

    /** 提醒通知渠道（默认重要性，会响）。 */
    const val NOTIFY_CHANNEL = "homework_reminder"

    /** 校验期间的静默前台服务通知渠道（最低重要性，不打扰）。 */
    const val NOTIFY_CHANNEL_PROGRESS = "homework_reminder_progress"

    /** 正式提醒的通知 id 基数（每条排期一个稳定 id）。 */
    const val NOTIFICATION_ID_BASE = 7300

    /** 前台服务占位通知的 id。 */
    const val PROGRESS_NOTIFICATION_ID = 7299

    /**
     * 点击通知要跳到的目标：复用小组件的 `widget_target` extra 与
     * `MainActivity.consumeIntentTarget`，因此点通知会直接切到作业页。
     */
    const val EXTRA_TARGET = "widget_target"
    const val TARGET_HOMEWORK = "homework"

    /**
     * 校验服务整体等待上限（超过就按"校验失败"处理，照常提醒）。
     *
     * 30s = Dart 侧"补拉课程列表 8s + 抓作业 15s"的最坏情况 + 引擎启动余量。
     * 不能设太小：超时先到会把还在跑校验的引擎销毁掉，白等一场。
     */
    const val CHECK_TIMEOUT_MS = 30_000L
}
