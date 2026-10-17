package com.zys.myschedule.widget

/**
 * Dart ↔ Kotlin 的 schema 契约常量。
 *
 * **唯一事实来源在 Dart 侧**（`widget_snapshot_service.kWidgetSnapshotVersion`）；
 * 这里复制同一数值。字段含义变化时两边必须同改，否则 Kotlin 会把
 * 不认识的版本按空态处理（"请打开 App 更新"），不会崩。
 */
object WidgetSnapshotContract {
    const val VERSION = 2

    /** MethodChannel 名（Dart 侧 `widgetChannel` 必须一致）。 */
    const val CHANNEL_WIDGET = "com.zys.myschedule/widget"

    /** 点击跳转通道（Dart 侧 `widgetNavChannel` 必须一致）。 */
    const val CHANNEL_NAV = "com.zys.myschedule/nav"

    /** PendingIntent extra：点击小组件后要打开的页面目标。 */
    const val EXTRA_TARGET = "widget_target"

    /** 目标值，与 Dart `WidgetTarget` 枚举的 name 一一对应。 */
    const val TARGET_HOME = "home"
    const val TARGET_HOMEWORK = "homework"
    const val TARGET_EXAM = "exam"

    /**
     * pin（添加到桌面）结果广播：`requestPinAppWidget` 的 successCallback
     * 用这个 action 发进 [WidgetPinResultReceiver]。
     */
    const val ACTION_PIN_RESULT = "com.zys.myschedule.action.WIDGET_PIN_RESULT"

    /** 结果广播里的卡片类型 extra（值 = Dart `WidgetKind.name`）。 */
    const val EXTRA_PIN_KIND = "widget_pin_kind"

    /** Kotlin → Dart 通道方法名：pin 结果（与 Dart 侧 `onPinResult` 一致）。 */
    const val METHOD_ON_PIN_RESULT = "onPinResult"
}
