package com.zys.myschedule

import android.Manifest
import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Log
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import com.zys.myschedule.reminder.HomeworkReminderFireService
import com.zys.myschedule.reminder.HomeworkReminderNotifier
import com.zys.myschedule.reminder.HomeworkReminderScheduler
import com.zys.myschedule.reminder.ReminderContract
import com.zys.myschedule.widget.WidgetPinBridge
import com.zys.myschedule.widget.WidgetPinRequest
import com.zys.myschedule.widget.WidgetSnapshotContract
import com.zys.myschedule.widget.WidgetSnapshotRepository
import com.zys.myschedule.widget.WidgetUpdater
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：在 Flutter 标准宿主之外多了几条原生通道。
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
 *
 * 4. `com.zys.myschedule/login_qr`（Dart → Kotlin）：校外扫码登录，
 *    把 CAS 二维码写进相册并拉起微信扫一扫。
 */
class MainActivity : FlutterActivity() {

    private var navMethodChannel: MethodChannel? = null
    private var widgetMethodChannel: MethodChannel? = null

    /** Android 7–9 保存相册前的运行时权限申请；等待回调期间暂存参数。 */
    private var pendingQrSave: PendingQrSave? = null

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
                    Log.i(TAG_NAV, "Dart 取初始目标：$target")
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
                    // 主 ABI（`arm64-v8a` / `armeabi-v7a` / `x86_64`）：检查更新时
                    // 用它挑裁剪包，避免每次都拉 58MB 的通用包。
                    "primaryAbi" ->
                        result.success(SystemSettingsBridge.primaryAbi())
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

        // 4. `com.zys.myschedule/login_qr`（Dart → Kotlin）：校外扫码登录。
        //    - saveImageToGallery：二维码写系统相册（Android 10+ 免权限）；
        //    - openWeChatScanner：拉起微信扫一扫（weixin://dl/scan）；
        //    - isWeChatInstalled / deleteImage：判断安装、登录后清理。
        val loginQr = MethodChannel(messenger, "com.zys.myschedule/login_qr")
        loginQr.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "campus_login_qr.png"
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("bad_args", "bytes 为空", null)
                    } else {
                        saveImageToGallery(bytes, name, result)
                    }
                }

                "openWeChatScanner" -> result.success(openWeChatScanner())
                "isWeChatInstalled" -> result.success(isWeChatInstalled())
                "deleteImage" -> result.success(deleteImage(call.argument<String>("uri")))
                else -> result.notImplemented()
            }
        }

        // 5. `com.zys.myschedule/reminder`（Dart → Kotlin）：作业提醒。
        //    Dart 算好排期（哪些作业、什么时刻提醒）下发；本侧只负责
        //    "排闹钟 / 发通知 / 报权限状态"，不认识作业与插件。
        //    通知渠道在这里建一次，保证系统设置页里能看到"作业提醒"分组。
        HomeworkReminderNotifier.ensureChannels(applicationContext)
        MethodChannel(messenger, ReminderContract.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncPlan" -> {
                        val json = call.argument<String>("json")
                        if (json.isNullOrBlank()) {
                            result.error("bad_args", "json 为空", null)
                        } else {
                            result.success(
                                HomeworkReminderScheduler.sync(applicationContext, json),
                            )
                        }
                    }

                    "cancelAll" -> {
                        HomeworkReminderScheduler.cancelAll(applicationContext)
                        result.success(null)
                    }

                    "hasNotificationPermission" ->
                        result.success(
                            HomeworkReminderNotifier.canPost(applicationContext),
                        )

                    "requestNotificationPermission" ->
                        result.success(requestNotificationPermission())

                    "canScheduleExactAlarms" -> {
                        val am = getSystemService(AlarmManager::class.java)
                        result.success(
                            am != null && HomeworkReminderScheduler.canScheduleExact(am),
                        )
                    }

                    "openExactAlarmSettings" ->
                        result.success(openExactAlarmSettings())

                    "openNotificationSettings" ->
                        result.success(openNotificationSettings())

                    "showTestNotification" ->
                        result.success(
                            HomeworkReminderNotifier.postTest(applicationContext),
                        )

                    // 登记后台校验入口句柄：闹钟触发时用它起临时引擎。
                    "registerCheckHandle" -> {
                        val handle = call.argument<Number>("handle")?.toLong() ?: 0L
                        getSharedPreferences(ReminderContract.PREFS, MODE_PRIVATE)
                            .edit()
                            .putLong(ReminderContract.PREF_CHECK_HANDLE, handle)
                            .apply()
                        result.success(handle != 0L)
                    }

                    // 设置页「立即测试完整链路」：与闹钟触发走同一段服务代码。
                    "runCheckNow" -> {
                        val itemJson = call.argument<String>("itemJson").orEmpty()
                        result.success(
                            try {
                                HomeworkReminderFireService.start(
                                    applicationContext,
                                    itemJson,
                                )
                                itemJson.isNotEmpty()
                            } catch (e: Exception) {
                                false
                            },
                        )
                    }

                    else -> result.notImplemented()
                }
            }

        // 引擎刚配好：如果启动 intent 里带着点击目标，转存起来等 Dart 取。
        consumeIntentTarget(intent)?.let {
            pendingLaunchTarget = it
            Log.i(TAG_NAV, "冷启动暂存 target=$it")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // App 已在运行：直接推给 Dart 的 handler；
        // handler 还没注册（极端情况）时目标暂存，等下次 takeInitialTarget。
        val target = consumeIntentTarget(intent)
        Log.i(TAG_NAV, "onNewIntent target=$target channelReady=${navMethodChannel != null}")
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
        pendingQrSave = null
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

    // ───────────────────── 校外扫码登录 ─────────────────────

    /**
     * 把二维码 PNG 写进系统相册。
     *
     * - Android 10+：MediaStore + IS_PENDING，不需要存储权限；
     * - Android 7–9：需要 WRITE_EXTERNAL_STORAGE，先申请再写。
     *
     * 返回 `content://` URI 字符串，供 Dart 侧登录完成后删除。
     */
    private fun saveImageToGallery(
        bytes: ByteArray,
        name: String,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingQrSave = PendingQrSave(bytes, name, result)
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQ_QR_SAVE,
            )
            return
        }

        try {
            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/CampusAssistant",
                    )
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val inserted = contentResolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: throw IllegalStateException("MediaStore 插入失败")
                contentResolver.openOutputStream(inserted)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("无法打开相册输出流")
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(inserted, values, null, null)
                inserted
            } else {
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: throw IllegalStateException("二维码解码失败")
                @Suppress("DEPRECATION")
                val path = MediaStore.Images.Media.insertImage(
                    contentResolver,
                    bitmap,
                    name,
                    null,
                ) ?: throw IllegalStateException("相册写入失败")
                Uri.parse(path)
            }
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("save_failed", e.message ?: "保存二维码失败", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_QR_SAVE) return
        val pending = pendingQrSave ?: return
        pendingQrSave = null
        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            saveImageToGallery(pending.bytes, pending.name, pending.result)
        } else {
            pending.result.error("permission_denied", "未授予存储权限", null)
        }
    }

    /** 拉起微信扫一扫；未安装微信 / 没有对应 Activity 返回 false。 */
    private fun openWeChatScanner(): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("weixin://dl/scan")).apply {
            setPackage("com.tencent.mm")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: Exception) {
            false
        }
    }

    private fun isWeChatInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo("com.tencent.mm", 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    /** 删除登录二维码；找不到 / 已删除返回 false。 */
    private fun deleteImage(uri: String?): Boolean {
        if (uri.isNullOrBlank()) return false
        return try {
            contentResolver.delete(Uri.parse(uri), null, null) > 0
        } catch (e: Exception) {
            false
        }
    }

    // ───────────────────── 作业提醒（Phase 9）─────────────────────

    /**
     * 申请通知权限（Android 13+）。
     *
     * 返回 `true` 表示"弹窗已拉起或本来就已授权"——系统弹窗是异步的，
     * Dart 侧稍后再查 [HomeworkReminderNotifier.canPost] 拿真实结果。
     */
    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return HomeworkReminderNotifier.canPost(applicationContext)
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_NOTIFICATIONS,
        )
        return true
    }

    /** 跳系统"闹钟和提醒"授权页（Android 12+）。 */
    private fun openExactAlarmSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /** 跳本应用的通知设置页（用户把通知关掉后的补救入口）。 */
    private fun openNotificationSettings(): Boolean {
        return try {
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (e: Exception) {
            // 极老系统没有该页面：退回应用详情页。
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                true
            } catch (inner: Exception) {
                false
            }
        }
    }

    /** Android 7–9 存储权限回调期间暂存的保存请求。 */
    private data class PendingQrSave(
        val bytes: ByteArray,
        val name: String,
        val result: MethodChannel.Result,
    )

    companion object {
        private const val TAG_NAV = "WidgetNav"

        /** 保存二维码前的运行时权限请求码（与小组件无关，取个不冲突的值）。 */
        private const val REQ_QR_SAVE = 4701

        /** 通知权限（Android 13+）的请求码。 */
        private const val REQ_NOTIFICATIONS = 4702

        /**
         * 冷启动时暂存的小组件点击目标（Dart 侧 `WidgetNav` 来取）。
         * @Volatile：主线程与 Dart bridge 线程都可能访问。
         */
        @Volatile
        var pendingLaunchTarget: String? = null
            private set
    }
}
