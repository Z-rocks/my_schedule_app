package com.zys.myschedule

import android.content.Intent
import com.zys.myschedule.widget.WidgetPinBridge
import com.zys.myschedule.widget.WidgetPinRequest
import com.zys.myschedule.widget.WidgetSnapshotContract
import com.zys.myschedule.widget.WidgetSnapshotRepository
import com.zys.myschedule.widget.WidgetUpdater
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：在 Flutter 标准宿主之外多了两条小组件通道。
 *
 * 1. `com.zys.myschedule/widget`（Dart → Kotlin）：
 *    - `writeSnapshot({json})`：Dart 把课表/作业/考试快照 JSON 发来，
 *      本类原子写入 `filesDir/widget/schedule_snapshot.json`（Hive 的
 *      .hive 是 Dart 私有格式，Kotlin 读不了，所以不走文件直接读）。
 *    - `refresh()`：触发所有已添加的 AppWidget 重读快照重渲染。
 *
 * 2. `com.zys.myschedule/nav`（Kotlin → Dart）：
 *    - Dart 启动后调 `takeInitialTarget` 取冷启动时暂存的目标；
 *    - App 已在运行时收到新 intent（卡片被再次点击，singleTop →
 *      [onNewIntent]）时，Dart 侧置了 handler 就 `invokeMethod("onTarget")`。
 *
 * 3. `com.zys.myschedule/system`（Dart → Kotlin）：小组件省电引导，
 *    跳系统应用信息页 / 电池优化列表。
 */
class MainActivity : FlutterActivity() {

    private var navMethodChannel: MethodChannel? = null
    private var widgetMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val widgetChannel = MethodChannel(messenger, WidgetSnapshotContract.CHANNEL_WIDGET)
        widgetMethodChannel = widgetChannel
        // pin 结果（WidgetPinResultReceiver）要回推给 Dart，同一个通道双向用。
        WidgetPinBridge.attach(widgetChannel)
        widgetChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "writeSnapshot" -> {
                        val json = call.argument<String>("json")
                        if (json.isNullOrBlank()) {
                            result.error("bad_args", "json 为空", null)
                        } else {
                            try {
                                WidgetSnapshotRepository(applicationContext).write(json)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("write_failed", e.message, null)
                            }
                        }
                    }

                    "refresh" -> {
                        WidgetUpdater.refreshAll(applicationContext)
                        result.success(null)
                    }

                    // W5 真机修复：应用内直接请求添加小部件。
                    // 只走系统 pin（Android 8.0+ 标准能力），桌面自己弹确认。
                    // Dart 侧 widget_bridge.dart 的 requestPinWidget。
                    "requestPinWidget" -> {
                        val kind = call.argument<String>("kind")
                        if (kind.isNullOrBlank()) {
                            result.error("bad_args", "kind 为空", null)
                        } else {
                            result.success(
                                WidgetPinRequest.requestPin(applicationContext, kind),
                            )
                        }
                    }

                    "isPinWidgetSupported" ->
                        result.success(
                            WidgetPinRequest.isSupported(applicationContext),
                        )

                    // 桌面上是否已经有这类卡片（真实结果，供引导页显示状态）。
                    "isWidgetAdded" -> {
                        val kind = call.argument<String>("kind")
                        result.success(
                            if (kind.isNullOrBlank()) {
                                false
                            } else {
                                WidgetPinRequest.isAdded(applicationContext, kind)
                            },
                        )
                    }

                    else -> result.notImplemented()
                }
            }

        val nav = MethodChannel(messenger, WidgetSnapshotContract.CHANNEL_NAV)
        navMethodChannel = nav
        nav.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeInitialTarget" -> {
                    // 冷启动竞态：卡片拉起 App 时 Dart 引擎还没起来，
                    // extra 先暂存在 pendingLaunchTarget，等 Dart 侧来取。
                    val target = pendingLaunchTarget
                    pendingLaunchTarget = null
                    result.success(target)
                }

                else -> result.notImplemented()
            }
        }

        // 3. `com.zys.myschedule/system`（Dart → Kotlin）：省电引导跳系统设置。
        MethodChannel(messenger, SystemSettingsBridge.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "manufacturer" ->
                        result.success(SystemSettingsBridge.manufacturer())
                    "openAppDetails" ->
                        result.success(
                            SystemSettingsBridge.openAppDetails(applicationContext),
                        )
                    "openBatterySettings" ->
                        result.success(
                            SystemSettingsBridge.openBatterySettings(applicationContext),
                        )
                    // 小组件加不上时的补救入口：权限管理 → 其他权限 → 桌面快捷方式
                    // （小米 MIUIOP 10017，默认拒绝，用户允许后 pin 立刻可用）。
                    "openPermissionEditor" ->
                        result.success(
                            SystemSettingsBridge.openPermissionEditor(applicationContext),
                        )
                    // 版本号的唯一真相：从系统读 versionName+versionCode，
                    // 避免 Dart 侧再维护一份常量（曾写死 v0.1.0 与实际包不符）。
                    "appVersion" ->
                        result.success(
                            SystemSettingsBridge.appVersion(applicationContext),
                        )
                    // 检查更新 → 前往下载：用系统浏览器打开 Release 页面。
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        result.success(
                            SystemSettingsBridge.openUrl(applicationContext, url),
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        // 引擎刚配好：如果启动 intent 里带着点击目标，转存起来等 Dart 取。
        consumeIntentTarget(intent)?.let { pendingLaunchTarget = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // App 已在运行：直接推给 Dart 的 handler；
        // handler 还没注册（极端情况）时目标暂存，等下次 takeInitialTarget。
        val target = consumeIntentTarget(intent)
        if (target != null) {
            val channel = navMethodChannel
            if (channel != null) {
                try {
                    channel.invokeMethod("onTarget", target)
                } catch (e: Exception) {
                    pendingLaunchTarget = target
                }
            } else {
                pendingLaunchTarget = target
            }
        }
    }

    override fun onDestroy() {
        // 引擎销毁后通道失效：解除桥接，避免 pin 结果回调打到已死的通道。
        widgetMethodChannel?.let { WidgetPinBridge.detach(it) }
        widgetMethodChannel = null
        navMethodChannel = null
        super.onDestroy()
    }

    /** 取出并清掉 intent 里的 widget 目标；没有返回 null。 */
    private fun consumeIntentTarget(intent: Intent?): String? {
        val target = intent?.getStringExtra(WidgetSnapshotContract.EXTRA_TARGET)
        if (!target.isNullOrEmpty()) {
            intent.removeExtra(WidgetSnapshotContract.EXTRA_TARGET)
        }
        return if (target.isNullOrEmpty()) null else target
    }

    companion object {
        /**
         * 冷启动时暂存的小组件点击目标（Dart 侧 `WidgetNav` 来取）。
         * @Volatile：主线程与 Dart bridge 线程都可能访问。
         */
        @Volatile
        var pendingLaunchTarget: String? = null
            private set
    }
}
