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

/**
 * 作业提醒通知：渠道创建 + 发通知 + 权限判断。
 *
 * 全部走平台 API（不用 androidx.core 的 NotificationCompat）：
 * minSdk 24 只有 Android 7.0，NotificationChannel 走 26+ 分支即可，
 * 少一个依赖也少一处版本错配的可能。
 */
object HomeworkReminderNotifier {

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

    /** 建渠道（幂等，重复调用无副作用）。 */
    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(ReminderContract.NOTIFY_CHANNEL) == null) {
            val channel = NotificationChannel(
                ReminderContract.NOTIFY_CHANNEL,
                "作业提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "作业快到截止时间时提醒（可在设置里调整提醒次数与提前量）"
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        }
        if (nm.getNotificationChannel(ReminderContract.NOTIFY_CHANNEL_PROGRESS) == null) {
            // 校验期间的占位通知：静音、无振动、不亮屏——用户基本察觉不到。
            val channel = NotificationChannel(
                ReminderContract.NOTIFY_CHANNEL_PROGRESS,
                "作业提醒校验",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "提醒前检查作业状态时短暂显示"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }
    }

    /** 校验期间的前台服务占位通知。 */
    fun buildProgress(context: Context): Notification {
        ensureChannels(context)
        val builder = newBuilder(context, ReminderContract.NOTIFY_CHANNEL_PROGRESS)
        builder.setSmallIcon(R.drawable.ic_notification_homework)
            .setContentTitle("正在检查作业状态")
            .setContentText("确认这份作业是否已提交…")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
        return builder.build()
    }

    /** 发一条正式提醒。 */
    fun post(context: Context, item: ReminderItem, suffix: String = ""): Boolean {
        if (!canPost(context)) return false
        ensureChannels(context)
        val builder = newBuilder(context, ReminderContract.NOTIFY_CHANNEL)
        builder.setSmallIcon(R.drawable.ic_notification_homework)
            .setContentTitle(item.notificationTitle)
            .setContentText(item.notificationBody + suffix)
            .setStyle(Notification.BigTextStyle().bigText(item.notificationBody + suffix))
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setContentIntent(contentIntent(context))
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return try {
            nm.notify(item.notificationId, builder.build())
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /** 直接从排期 JSON 发通知（引擎起不来时的兜底路径）。 */
    fun postFromJson(context: Context, itemJson: String): Boolean {
        val item = ReminderItem.fromJson(itemJson) ?: return false
        return post(context, item, "（未能确认提交状态）")
    }

    /** 设置页"发一条测试通知"。 */
    fun postTest(context: Context): Boolean {
        if (!canPost(context)) return false
        ensureChannels(context)
        val builder = newBuilder(context, ReminderContract.NOTIFY_CHANNEL)
        builder.setSmallIcon(R.drawable.ic_notification_homework)
            .setContentTitle("作业提醒 · 测试")
            .setContentText("通知能用，作业快截止时就会这样提醒你。")
            .setStyle(
                Notification.BigTextStyle()
                    .bigText("通知能用，作业快截止时就会这样提醒你。\n正式提醒会先查一次作业状态，已提交的不打扰。"),
            )
            .setAutoCancel(true)
            .setContentIntent(contentIntent(context))
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return try {
            nm.notify(ReminderContract.NOTIFICATION_ID_BASE - 1, builder.build())
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /**
     * 点通知 → 打开 App 并切到作业页（复用小组件的 `widget_target` 机制）。
     *
     * ## ⚠️ 绝对不能给 intent 设 `data` URI
     *
     * Flutter 3.10+ 会把 Activity 收到的 intent `data` 当作**深链**交给
     * `WidgetsApp`，后者会为此 push 一个**新路由**；新路由里 `home` 又被建了
     * 一次（新的 `HomePage`，默认停在课表页），正好盖在我们切好的 tab 上面。
     * 表现就是"日志显示切到了作业页，界面上却还是课表"。
     * 小组件的 `widgetLaunchIntent` 同样只带 extra、不带 data，照它写就对了。
     */
    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(ReminderContract.EXTRA_TARGET, ReminderContract.TARGET_HOMEWORK)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(context, 7100, intent, flags)
    }

    private fun newBuilder(context: Context, channelId: String): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
    }
}
