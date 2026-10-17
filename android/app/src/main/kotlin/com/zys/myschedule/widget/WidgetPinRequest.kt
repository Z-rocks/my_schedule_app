package com.zys.myschedule.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * 小组件添加请求（"添加到桌面"）。
 *
 * ## 只走系统原生 pin，不再走小米小部件中心
 *
 * 2026-10-17 反编译 HyperOS 桌面（com.miui.home RELEASE-7.50.06）取证结论
 * （详见 docs/widget_task_breakdown.md 6.3）：
 *
 * - 系统 pin（`requestPinAppWidget`）在 HyperOS 上是**能用的**：
 *   请求落到 `com.miui.home/.launcher.AddItemActivity`，
 *   `requestType == 2`（APPWIDGET）时会先试
 *   `MIUIWidgetUtil.startWidgetDetailPage(...)`；返回 false 才走标准
 *   `showPinWidgetConfirmDialog()` → `InstallWidgetReceiver.addWidget()` 真正落桌面。
 * - `startWidgetDetailPage` 的第一条判断就是 `isMIUIWidget(provider)`，
 *   它读的是**接收器上的 `miuiWidget` meta-data**。旧版 manifest 声明了它，
 *   于是 pin 被改道去开"小部件中心 · 应用详情页"——那个页面的内容来自小米
 *   云端目录（PickerDetailRepository → 远端接口），未上架应用永远是空的。
 *   表现就是：返回值 true、没有确认弹窗、桌面什么都没有。
 * - 所以现在 manifest 里那三项小米声明已全部移除，本类**只调系统 pin**，
 *   并且用 `successCallback`（PendingIntent 广播）区分"真的加进桌面"和
 *   "用户取消 / 桌面不支持"——返回 true 只代表"系统接单"。
 *
 * 失败时返回 false，由 Dart 侧给出手动引导文案（长按桌面空白处 → 添加小部件）。
 */
object WidgetPinRequest {

    /** Dart 侧 [WidgetKind] 的字符串与 Kotlin provider 类的映射。 */
    private val PROVIDERS: Map<String, Class<out android.appwidget.AppWidgetProvider>> =
        mapOf(
            "today" to TodayWidgetProvider::class.java,
            "week" to WeekWidgetProvider::class.java,
            "homework" to HomeworkWidgetProvider::class.java,
            "exam" to ExamWidgetProvider::class.java,
        )

    /** 当前桌面是否支持"应用请求固定小部件"（Android 8.0+ 标准能力）。 */
    fun isSupported(context: Context): Boolean =
        AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported

    /**
     * 桌面上是否已经加了这类卡片（至少 1 张）。
     *
     * 这是**真实结果**的唯一可靠来源：pin 的返回值 / 回调都只表示"系统接单"，
     * 只有 `getAppWidgetIds` 非空才说明卡片真的绑进了某个桌面。
     * 引导页用它显示"已添加"状态。
     */
    fun isAdded(context: Context, kind: String): Boolean {
        val providerClass = PROVIDERS[kind] ?: return false
        return try {
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, providerClass))
                .isNotEmpty()
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 请求把指定类型的卡片加到桌面。
     *
     * @return true = 系统已接单（桌面会弹确认，确认后卡片才真正落桌面）。
     *   false = 类型未知、桌面不支持或调用异常——调用方应回退到手动引导。
     */
    fun requestPin(context: Context, kind: String): Boolean {
        val providerClass = PROVIDERS[kind] ?: return false
        val manager = AppWidgetManager.getInstance(context)
        if (!manager.isRequestPinAppWidgetSupported) return false
        val component = ComponentName(context, providerClass)
        return try {
            // extras 必须为 null：AddItemActivity 里 extras != null 才可能触发
            // startWidgetDetailPage 的云端详情页分支，null 直接走标准确认弹窗。
            manager.requestPinAppWidget(
                component,
                null,
                pinResultIntent(context, kind, providerClass),
            )
        } catch (_: Exception) {
            false
        }
    }

    /**
     * pin 的 successCallback：卡片**真的加进桌面**后由系统发出，
     * 里面带 `AppWidgetManager.EXTRA_APPWIDGET_ID`；用户取消则不带。
     * 用 requestCode 区分卡片类型，避免 4 张卡的 PendingIntent 互相覆盖。
     */
    private fun pinResultIntent(
        context: Context,
        kind: String,
        providerClass: Class<*>,
    ): PendingIntent {
        val intent = Intent(context, WidgetPinResultReceiver::class.java).apply {
            action = WidgetSnapshotContract.ACTION_PIN_RESULT
            putExtra(WidgetSnapshotContract.EXTRA_PIN_KIND, kind)
        }
        return PendingIntent.getBroadcast(
            context,
            providerClass.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
