package com.zys.myschedule

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * 小组件"省电引导"用的系统设置跳转（Phase W5）。
 *
 * 厂商（MIUI/HyperOS、EMUI、ColorOS、OriginOS…）杀后台会影响
 * "App 数据变化后主动推快照给小组件"的及时性，所以设置里给出引导。
 * 各家自启动管理页 Intent 不公开且版本间变动大，**不做厂商深链**，
 * 只跳两个标准页：
 * - 应用信息页（用户从这里找"省电策略 / 自启动"入口，位置各家不同但都可达）；
 * - 电池优化列表页（标准 AOSP 页，各厂商都有对应实现）。
 */
object SystemSettingsBridge {

    const val CHANNEL: String = "com.zys.myschedule/system"

    /** 设备厂商（小写，如 `xiaomi` / `huawei` / `oppo`）。取不到返回空串。 */
    fun manufacturer(): String = Build.MANUFACTURER?.lowercase() ?: ""

    /** 打开本应用的系统信息页（权限 / 省电策略 / 自启动通常都在里面）。 */
    fun openAppDetails(context: Context): Boolean {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        )
        return start(context, intent)
    }

    /** 打开系统"电池优化 / 忽略电池优化"列表页（标准 AOSP Action）。 */
    fun openBatterySettings(context: Context): Boolean {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        return start(context, intent)
    }

    /**
     * 打开本应用的**权限管理页**（"添加到桌面"失败时的补救入口）。
     *
     * 小米/HyperOS 上有一个 AOSP 没有的门槛：桌面在把小部件真正落桌面之前会检查
     * 小米自定义 app-op **MIUIOP(10017)「桌面快捷方式」**，默认是"拒绝"
     * （真机 logcat：`add widget failed, <pkg> has no permission`）。
     * 用户手动允许后立刻生效，本方法就是把用户送到那个开关所在的页面：
     * 应用信息 → 权限管理 → 其他权限 → 桌面快捷方式。
     *
     * 这是**用户授权页**而非厂商私有 SDK 深链：Intent 是 MIUI 公开的
     * `miui.intent.action.APP_PERM_EDITOR`，打不开就退回标准的应用信息页
     *（用户在那里面点"权限管理"是同样的两步）。
     */
    fun openPermissionEditor(context: Context): Boolean {
        val miuiIntent = Intent("miui.intent.action.APP_PERM_EDITOR").apply {
            putExtra("extra_pkgname", context.packageName)
            putExtra("extra_package_name", context.packageName)
        }
        if (start(context, miuiIntent)) return true
        return openAppDetails(context)
    }

    /**
     * 读取本应用的版本号，形如 `0.2.0+2`（versionName + versionCode）。
     *
     * **这是版本号的唯一真相来源**：`pubspec.yaml` 的 `version` 由 Flutter
     * 构建时写入 AndroidManifest（versionName / versionCode），这里从系统
     * 读回来，就不需要在 Dart 里再维护一份常量——两份版本号必然漂移
     * （此前设置页写死 `v0.1.0`，而实际包是 `0.2.0+2`）。
     *
     * 读不到时返回空串，由 Dart 侧决定兜底显示。
     */
    /**
     * 用系统浏览器打开一个 **http / https** 链接（"检查更新 → 前往下载"用）。
     *
     * 只放行这两种 scheme：这个入口的 URL 来自远端 Release 数据，
     * 放行 `intent://` / `file://` 之类会让远端数据能启动任意组件。
     */
    fun openUrl(context: Context, url: String): Boolean {
        val trimmed = url.trim()
        if (trimmed.isEmpty()) return false
        val uri = try {
            Uri.parse(trimmed)
        } catch (e: Exception) {
            return false
        }
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme != "http" && scheme != "https") return false
        return start(context, Intent(Intent.ACTION_VIEW, uri))
    }

    @Suppress("DEPRECATION")
    fun appVersion(context: Context): String = try {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val name = info.versionName ?: ""
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
        if (name.isEmpty()) "" else "$name+$code"
    } catch (e: Exception) {
        // 个别定制 ROM / 极端情况下 getPackageInfo 可能抛，返回空串交给 Dart 兜底。
        ""
    }

    private fun start(context: Context, intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        // 个别精简 ROM 可能没有这个 Action：返回 false，让 Dart 侧提示手动路径。
        false
    }
}
