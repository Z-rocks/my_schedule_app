package com.zys.myschedule.reminder

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.zys.myschedule.MainActivity
import com.zys.myschedule.R
import org.json.JSONObject

/**
 * 上课提醒通知：渠道创建 + 发通知 + 权限判断。
 *
 * 全部走平台 API（不用 androidx.core 的 NotificationCompat），
 * 与 [HomeworkReminderNotifier] 保持一致。
 */
object ClassReminderNotifier {

    /** 是否已允许发通知（Android 13 以下只看用户是否在设置里关过）。 */
    fun canPost(context: Context): Boolean {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    /** 建渠道（幂等）。 */
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(ClassReminderContract.NOTIFY_CHANNEL) != null) return
        val channel = NotificationChannel(
            ClassReminderContract.NOTIFY_CHANNEL,
            "上课提醒",
            // 上课提醒比作业提醒更"卡点"（迟到就迟到了），所以用 HIGH：
            // 会响铃 + 弹横幅。用户嫌吵可以在系统设置里单独把这个渠道降级。
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "课前提醒（可在 设置 → 上课提醒 里调整提前量与开关）"
            enableVibration(true)
        }
        nm.createNotificationChannel(channel)
    }

    /** 发一条提醒。 */
    fun post(
        context: Context,
        notificationId: Int,
        title: String,
        body: String,
    ): Boolean {
        if (!canPost(context)) return false
        ensureChannel(context)
        val builder = newBuilder(context)
        builder.setSmallIcon(R.drawable.ic_notification_class)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setContentIntent(contentIntent(context))
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return try {
            nm.notify(notificationId, builder.build())
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /** 从排期 JSON 直接发（闹钟触发路径）。 */
    fun postFromJson(context: Context, itemJson: String): Boolean {
        return try {
            val obj = JSONObject(itemJson)
            val code = obj.optInt("requestCode", 0)
            val title = obj.optString("title")
            val body = obj.optString("body")
            if (code == 0 || title.isEmpty()) return false
            // 通知 id 用 requestCode 取模：同一节课重复触发时覆盖同一条通知，
            // 而不是在通知栏堆一列。
            post(
                context,
                ClassReminderContract.NOTIFICATION_ID_BASE + (code % 500),
                title,
                body,
            )
        } catch (e: Exception) {
            false
        }
    }

    /** 设置页"发一条测试通知"。 */
    fun postTest(context: Context): Boolean {
        return post(
            context,
            ClassReminderContract.NOTIFICATION_ID_TEST,
            "高等数学",
            "15 分钟后上课 · 第 3-4 节 · HE-405 · 10:25",
        )
    }

    /**
     * 点通知 → 打开 App 并切到课表页。
     *
     * ## ⚠️ 绝对不能给 intent 设 `data` URI
     *
     * Flutter 3.10+ 会把 Activity 收到的 intent `data` 当作深链交给
     * `WidgetsApp`，后者会 push 一个**新路由**，新路由里 `home` 又被建了一次
     * （默认停在课表页），正好盖在切好的 tab 上面。只带 extra、不带 data。
     */
    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(
                ClassReminderContract.EXTRA_TARGET,
                ClassReminderContract.TARGET_HOME,
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            })
        return PendingIntent.getActivity(context, 7501, intent, flags)
    }

    private fun newBuilder(context: Context): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, ClassReminderContract.NOTIFY_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
    }
}
