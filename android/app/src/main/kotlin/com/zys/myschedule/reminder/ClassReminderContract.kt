package com.zys.myschedule.reminder

/**
 * 上课提醒的 schema / 通道契约。
 *
 * **与作业提醒完全独立**（不同的通道、prefs、渠道、通知 id 段），
 * 原因：作业提醒的排期是"每份作业 × 每档提前量"，上课提醒是"每节课 × 一个提前量"，
 * 两者的生命周期和重排时机都不一样。共用一个 `syncPlan` 会互相覆盖——
 * 同步作业会把上课提醒冲掉，反之亦然。
 *
 * **唯一事实来源在 Dart 侧**（`services/class_reminder_plan.dart` 的
 * `toJson` 与 `ClassReminderService` 的排期版本号），这里只是同值副本。
 */
object ClassReminderContract {
    /** Dart → Kotlin 通道（Dart 侧 `ReminderBridge` 必须一致）。 */
    const val CHANNEL = "com.zys.myschedule/class_reminder"

    /** 排期 schema 版本（Dart `kClassReminderPlanVersion`）。 */
    const val PLAN_VERSION = 1

    /** 本功能专用的 SharedPreferences（与作业提醒分开）。 */
    const val PREFS = "class_reminder"

    /** 最近一次下发的排期 JSON（开机后据此重排）。 */
    const val PREF_PLAN_JSON = "plan_json"

    /** 已排的闹钟 requestCode 列表（StringSet）。 */
    const val PREF_SCHEDULED_CODES = "scheduled_codes"

    /** 闹钟触发广播 action。 */
    const val ACTION_FIRE = "com.zys.myschedule.action.CLASS_REMINDER_FIRE"

    /** 广播 intent 里携带的单条排期 JSON。 */
    const val EXTRA_ITEM = "class_reminder_item"

    /** 提醒通知渠道。 */
    const val NOTIFY_CHANNEL = "class_reminder"

    /** 正式提醒的通知 id 基数（每条排期一个稳定 id）。 */
    const val NOTIFICATION_ID_BASE = 7500

    /** 测试通知的 id。 */
    const val NOTIFICATION_ID_TEST = 7499

    /**
     * 点通知跳转目标：课表页。
     *
     * 复用小组件的 `widget_target` extra 与 `MainActivity.consumeIntentTarget`，
     * 因此和作业提醒（跳作业页）走同一条链路。
     */
    const val EXTRA_TARGET = "widget_target"
    const val TARGET_HOME = "home"
}
