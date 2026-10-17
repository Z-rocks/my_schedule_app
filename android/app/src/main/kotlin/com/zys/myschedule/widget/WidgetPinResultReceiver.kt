package com.zys.myschedule.widget

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodChannel

/**
 * pin（添加到桌面）结果的接收器。
 *
 * `AppWidgetManager.requestPinAppWidget(provider, extras, successCallback)` 的
 * 第三个参数就是这个 PendingIntent：**卡片真的被桌面加进工作区**后系统才发它，
 * 被用户取消 / 桌面不支持则不发或发出的 intent 不带 `EXTRA_APPWIDGET_ID`。
 * 这就是"接单 ≠ 成功"的分界线（见 docs P5 遗留项）。
 *
 * 收到后经 [WidgetPinBridge] 推给 Dart，引导页据此弹"已添加 / 已取消"。
 */
class WidgetPinResultReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WidgetSnapshotContract.ACTION_PIN_RESULT) return
        val kind = intent.getStringExtra(WidgetSnapshotContract.EXTRA_PIN_KIND) ?: return
        // 带 EXTRA_APPWIDGET_ID = 桌面真的建了卡片实例；不带 = 用户取消。
        // 但小米（HyperOS）走的是自己的 AddItemActivity，id 由桌面自己 allocate，
        // 回调里**不一定**带 EXTRA_APPWIDGET_ID（真机实测：卡片已落桌面却拿不到 id）。
        // 所以以"桌面上到底有没有这类卡片"为准，EXTRA 只当快速通道。
        val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        val accepted = appWidgetId >= 0 ||
            WidgetPinRequest.isAdded(context, kind)
        WidgetPinBridge.dispatch(kind, accepted, appWidgetId)
    }
}

/**
 * Kotlin → Dart 的 pin 结果通道。
 *
 * [channel] 由 `MainActivity.configureFlutterEngine` 注入（与快照通道同一个
 * MethodChannel，双向可用）。引擎不在（Flutter 面已销毁）时静默丢弃——
 * 引导页在 onResume 还会用 `WidgetPinRequest.isAdded` 兜底查一次真实状态，
 * 所以丢一次消息不影响正确性。
 */
object WidgetPinBridge {

    @Volatile
    private var channel: MethodChannel? = null

    fun attach(methodChannel: MethodChannel) {
        channel = methodChannel
    }

    fun detach(methodChannel: MethodChannel) {
        if (channel === methodChannel) channel = null
    }

    fun dispatch(kind: String, accepted: Boolean, appWidgetId: Int) {
        val current = channel ?: return
        try {
            current.invokeMethod(
                WidgetSnapshotContract.METHOD_ON_PIN_RESULT,
                mapOf(
                    "kind" to kind,
                    "accepted" to accepted,
                    "appWidgetId" to appWidgetId,
                ),
            )
        } catch (_: Exception) {
            // 引擎已销毁 / 通道已失效：忽略，引导页 onResume 会兜底查状态。
        }
    }
}
