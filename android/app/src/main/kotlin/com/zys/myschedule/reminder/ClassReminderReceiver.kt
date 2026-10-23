package com.zys.myschedule.reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 上课提醒的闹钟广播。
 *
 * 与作业提醒不同，这里**不需要前台服务**：作业提醒要到点起 Flutter 引擎
 * 回查"是否已提交"，而上课提醒的数据全在本地、排期时的快照就是事实，
 * 直接发通知即可（广播接收器的 10s 预算绰绰有余）。
 */
class ClassReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ClassReminderContract.ACTION_FIRE) return
        val itemJson = intent.getStringExtra(ClassReminderContract.EXTRA_ITEM) ?: return
        try {
            ClassReminderNotifier.postFromJson(context, itemJson)
        } catch (e: Exception) {
            Log.w(TAG, "上课提醒发送失败", e)
        }
    }

    private companion object {
        const val TAG = "ClassReminder"
    }
}
