package com.zys.myschedule.reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机 / 应用更新后重排闹钟。
 *
 * 系统的闹钟在重启后会全部清空（AlarmManager 不持久化），应用被覆盖安装后
 * 也一样。若不重排，用户"重启一次手机就再也收不到提醒"——这是最典型的
 * 静默失效，必须补上。
 *
 * 重排依据是 `SharedPreferences` 里的排期 JSON（Dart 上次下发的全量计划），
 * 因此这里不需要 Dart 参与。
 */
class ReminderBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            // 部分厂商（含小米）快速开机发的私有 action，多收一个不亏。
            "android.intent.action.QUICKBOOT_POWERON",
            -> {
                try {
                    HomeworkReminderScheduler.reschedule(context)
                } catch (e: Exception) {
                    Log.w(TAG, "开机重排失败", e)
                }
            }
        }
    }

    private companion object {
        const val TAG = "HomeworkReminder"
    }
}
