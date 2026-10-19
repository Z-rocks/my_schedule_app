package com.zys.myschedule.reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 闹钟到点广播。
 *
 * 只做一件事：把"要提醒哪一条"转交给 [HomeworkReminderFireService]。
 * 校验（查作业是否已提交）需要起 Flutter 引擎，耗时可能好几秒，
 * 广播接收器只有 10s 预算且不能可靠地长期存活，所以必须交给前台服务。
 *
 * 前台服务起不来时（厂商限制 / 系统拒绝）**退化为不校验直接提醒**：
 * 宁可多提醒一次，也不能因为校验链路坏了就漏掉截止。
 */
class HomeworkReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ReminderContract.ACTION_FIRE) return
        val itemJson = intent.getStringExtra(ReminderContract.EXTRA_ITEM) ?: return
        try {
            HomeworkReminderFireService.start(context, itemJson)
        } catch (e: Exception) {
            Log.w(TAG, "起校验服务失败，退化为直接提醒", e)
            HomeworkReminderNotifier.postFromJson(context, itemJson)
        }
    }

    private companion object {
        const val TAG = "HomeworkReminder"
    }
}
