package com.zys.myschedule.reminder

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

/**
 * 提醒触发时的"先校验、再通知"服务。
 *
 * ## 流程
 *
 * 1. 前台服务 + 静默占位通知（IMPORTANCE_MIN，用户基本看不到）；
 * 2. 起一个**临时 Flutter 引擎**，注册插件（Cookie 走 secure storage 需要）；
 * 3. 用 App 启动时登记的 `DartCallbackHandle` 执行
 *    `homeworkNotificationCheckMain`（Dart 侧 `homework_check_entry.dart`）；
 * 4. 等 Dart 回传 `{status: completed|pending|unknown, reason}`：
 *    - `completed` → **不打扰**（用户已在网页端交了作业）；
 *    - `pending`   → 正常提醒；
 *    - `unknown`   → 按用户设置：默认仍提醒（宁可多提醒，不可漏截止）；
 * 5. 销毁引擎、撤掉占位通知、`stopSelf()`。
 *
 * ## 超时与失败
 *
 * 25s 内没拿到结果（引擎起不来 / 插件卡住 / 断网）→ 按 `unknown` 处理。
 * 也就是说**任何失败都不会导致"该提醒却没提醒"**（除非用户显式关掉了
 * "校验失败仍提醒"）。
 *
 * ## 为什么不复用主引擎
 *
 * 闹钟触发时 App 通常不在前台，主引擎可能根本不存在；新建引擎是唯一
 * 可靠路径。同一个进程里两个引擎并存是 Flutter 支持的（多引擎）。
 */
class HomeworkReminderFireService : Service() {

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var itemJson: String = ""
    private var finished = false
    private val handler = Handler(Looper.getMainLooper())
    private val timeoutRunnable = Runnable {
        Log.w(TAG, "校验超时，按未确认处理")
        finish(null)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        itemJson = intent?.getStringExtra(ReminderContract.EXTRA_ITEM) ?: ""
        val item = ReminderItem.fromJson(itemJson)
        if (item == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        // 先挂占位通知，满足前台服务的要求（Android 8+ 5 秒内必须 startForeground）。
        startForeground(
            ReminderContract.PROGRESS_NOTIFICATION_ID,
            HomeworkReminderNotifier.buildProgress(this),
        )

        val handle = prefs().getLong(ReminderContract.PREF_CHECK_HANDLE, 0L)
        if (handle == 0L) {
            // App 启动时没登记到回调句柄（极少数情况）→ 不校验，直接提醒。
            Log.w(TAG, "未登记校验句柄，跳过校验")
            finish(null)
            return START_NOT_STICKY
        }

        try {
            startCheckEngine(handle)
        } catch (e: Throwable) {
            Log.w(TAG, "启动校验引擎失败", e)
            finish(null)
            return START_NOT_STICKY
        }

        handler.postDelayed(timeoutRunnable, ReminderContract.CHECK_TIMEOUT_MS)
        return START_NOT_STICKY
    }

    /** 起临时引擎并执行 Dart 校验入口。 */
    private fun startCheckEngine(handle: Long) {
        // 不要手动 FlutterLoader.startInitialization / ensureInitializationComplete：
        // FlutterEngine 构造时会自己完成，重复调用会触发
        // "FlutterJNI.init called more than once" 并把进程级单例重init一遍。
        // 同理，FlutterEngine(Context) 默认 automaticallyRegisterPlugins=true，
        // 再手动 registerWith 会造成插件重复注册。
        val newEngine = FlutterEngine(applicationContext)
        engine = newEngine

        val ch = MethodChannel(newEngine.dartExecutor.binaryMessenger, ReminderContract.CHANNEL_CHECK)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart 侧 handler 装好了，可以把作业信息发过去。
                "ready" -> {
                    result.success(null)
                    ch.invokeMethod("run", buildCheckPayload(), null)
                }

                // Dart 校验完成。
                "result" -> {
                    result.success(null)
                    finish(call.arguments as? Map<*, *>)
                }

                else -> result.notImplemented()
            }
        }

        val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
        if (info == null) {
            Log.w(TAG, "回调句柄无效（callbackHandle=$handle）")
            finish(null)
            return
        }
        Log.i(
            TAG,
            "校验入口：handle=$handle name=${info.callbackName} " +
                "library=${info.callbackLibraryPath}",
        )
        newEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(info.callbackLibraryPath, info.callbackName),
        )
    }

    /** 传给 Dart 的作业信息（字段与 `homework_check_entry.dart` 对齐）。 */
    private fun buildCheckPayload(): Map<String, Any?> {
        val item = ReminderItem.fromJson(itemJson) ?: return emptyMap()
        return mapOf(
            "homeworkId" to item.homeworkId,
            "pluginId" to item.pluginId,
            "title" to item.title,
            "courseId" to item.courseId,
            // courseRef 用字符串传：Dart 侧自己 JSON 解析，避免两边对象模型耦合。
            "courseRefJson" to item.courseRefJson,
        )
    }

    /**
     * 收尾：按校验结果决定发不发通知，然后清理资源。
     *
     * [arguments] 为 null 表示"没校验出来"（超时 / 引擎失败 / 未登记句柄）。
     */
    private fun finish(arguments: Map<*, *>?) {
        if (finished) return
        finished = true
        handler.removeCallbacks(timeoutRunnable)

        val item = ReminderItem.fromJson(itemJson)
        if (item != null) {
            when (val status = arguments?.get("status")?.toString()) {
                "completed" -> Log.i(TAG, "作业已提交，跳过提醒：${item.homeworkId}")
                "pending" -> HomeworkReminderNotifier.post(this, item)
                else -> {
                    val reason = arguments?.get("reason")?.toString().orEmpty()
                    Log.i(TAG, "状态未确认（$status / $reason），按设置决定是否提醒")
                    if (item.notifyWhenCheckFails) {
                        HomeworkReminderNotifier.post(this, item, "（未能确认提交状态）")
                    }
                }
            }
        }

        // 清理：撤占位通知 → 销毁引擎 → 停服务。
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            Log.w(TAG, "撤占位通知失败", e)
        }
        try {
            channel?.setMethodCallHandler(null)
            channel = null
            engine?.destroy()
            engine = null
        } catch (e: Exception) {
            Log.w(TAG, "销毁校验引擎失败", e)
        }
        stopSelf()
    }

    override fun onDestroy() {
        // 保险：服务被系统回收时也别留下引擎。
        finished = true
        handler.removeCallbacks(timeoutRunnable)
        try {
            engine?.destroy()
        } catch (_: Exception) {
        }
        engine = null
        super.onDestroy()
    }

    private fun prefs() =
        getSharedPreferences(ReminderContract.PREFS, Context.MODE_PRIVATE)

    companion object {
        private const val TAG = "HomeworkReminder"

        /** 启动校验服务（前台服务）。 */
        fun start(context: Context, itemJson: String) {
            val intent = Intent(context, HomeworkReminderFireService::class.java)
                .putExtra(ReminderContract.EXTRA_ITEM, itemJson)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
