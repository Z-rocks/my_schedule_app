// 作业提醒的原生通道封装（Dart → Kotlin）。
//
// 只做"转发 + 兜底"：任何平台不支持 / 通道不可用时返回安全默认值，
// **绝不抛异常**——提醒功能坏掉不该影响 App 正常使用。
//
// 通道契约（Kotlin 侧 `ReminderContract.CHANNEL` 必须一致）：
//   syncPlan(json)                  → bool  全量替换排期（先取消旧闹钟再排新的）
//   cancelAll()                     → void  取消全部提醒
//   hasNotificationPermission()     → bool  Android 13+ 通知权限
//   requestNotificationPermission() → bool  拉起系统授权弹窗（结果走系统回调）
//   canScheduleExactAlarms()        → bool  Android 12+ 精确闹钟权限
//   openExactAlarmSettings()        → bool  跳"闹钟和提醒"授权页
//   openNotificationSettings()      → bool  跳应用通知设置页
//   showTestNotification(title, body) → bool 立刻发一条测试通知
//   registerCheckHandle(handle)     → bool  登记后台校验入口的 Dart 回调句柄
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 作业提醒通道（Dart 侧）。
class ReminderBridge {
  ReminderBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.zys.myschedule/reminder');

  /// 是否支持原生提醒（目前只有 Android 实现了闹钟 + 通知）。
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 全量下发排期。返回是否成功交给原生调度。
  static Future<bool> syncPlan(String planJson) async {
    if (!isSupported) return false;
    try {
      final bool? ok = await _channel
          .invokeMethod<bool>('syncPlan', <String, dynamic>{'json': planJson});
      return ok ?? false;
    } catch (error) {
      debugPrint('[ReminderBridge] 下发排期失败：$error');
      return false;
    }
  }

  /// 取消全部提醒（关闭开关 / 清空数据时用）。
  static Future<void> cancelAll() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } catch (error) {
      debugPrint('[ReminderBridge] 取消排期失败：$error');
    }
  }

  /// 是否已授予通知权限（Android 13 以下恒为 true）。
  static Future<bool> hasNotificationPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasNotificationPermission') ??
          false;
    } catch (error) {
      debugPrint('[ReminderBridge] 查询通知权限失败：$error');
      return false;
    }
  }

  /// 拉起系统通知授权弹窗。
  ///
  /// 系统弹窗是异步的，本方法只表示"弹窗已拉起"；真实结果请稍后再查
  /// [hasNotificationPermission]（用户点完弹窗才更新）。
  static Future<bool> requestNotificationPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel
              .invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } catch (error) {
      debugPrint('[ReminderBridge] 申请通知权限失败：$error');
      return false;
    }
  }

  /// 是否允许精确闹钟（Android 12+ 需要用户单独授权）。
  static Future<bool> canScheduleExactAlarms() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ??
          false;
    } catch (error) {
      debugPrint('[ReminderBridge] 查询精确闹钟权限失败：$error');
      return false;
    }
  }

  /// 跳系统"闹钟和提醒"授权页。
  static Future<bool> openExactAlarmSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openExactAlarmSettings') ??
          false;
    } catch (error) {
      debugPrint('[ReminderBridge] 打开精确闹钟设置失败：$error');
      return false;
    }
  }

  /// 跳应用通知设置页（用户手动关过通知时的补救入口）。
  static Future<bool> openNotificationSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } catch (error) {
      debugPrint('[ReminderBridge] 打开通知设置失败：$error');
      return false;
    }
  }

  /// 立刻发一条测试通知（设置页"试一下"按钮）。
  static Future<bool> showTestNotification({
    required String title,
    required String body,
  }) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'showTestNotification',
            <String, dynamic>{'title': title, 'body': body},
          ) ??
          false;
    } catch (error) {
      debugPrint('[ReminderBridge] 发测试通知失败：$error');
      return false;
    }
  }

  /// 立刻走一遍完整的"校验 → 通知"链路（设置页「立即测试完整链路」）。
  ///
  /// 与真实闹钟触发走**同一段原生代码**（`HomeworkReminderFireService`），
  /// 所以能验证引擎启动、插件加载、API 查询是否都正常。
  static Future<bool> runCheckNow(String itemJson) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'runCheckNow',
            <String, dynamic>{'itemJson': itemJson},
          ) ??
          false;
    } catch (error) {
      debugPrint('[ReminderBridge] 立即测试链路失败：$error');
      return false;
    }
  }

  /// 把后台校验入口的 Dart 回调句柄登记给原生。
  ///
  /// 原生在闹钟触发时用这个句柄起一个临时 Flutter 引擎执行
  /// `homeworkNotificationCheckMain`（见 `homework_check_entry.dart`）。
  /// 句柄只在 App 启动时登记一次；未登记时原生退化为"不校验直接提醒"。
  static Future<bool> registerCheckHandle(int rawHandle) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'registerCheckHandle',
            <String, dynamic>{'handle': rawHandle},
          ) ??
          false;
    } catch (error) {
      debugPrint('[ReminderBridge] 登记后台校验句柄失败：$error');
      return false;
    }
  }
}
